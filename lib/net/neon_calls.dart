import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../data/providers.dart';
import 'api.dart';
import 'neon_backend.dart';
import 'wire.dart';

/// Calls phone to phone over WebRTC (K1–K4). Set-up travels as sealed
/// mail: the caller's offer rings the other phone, the answer connects,
/// and either side can decline or end. Each SDP waits for its ICE
/// candidates first, so two messages are enough to connect. Only public
/// STUN is used (no TURN server), so some networks can't connect.
class NeonCalls implements CallLink {
  NeonCalls(this.b) {
    _signals = b.callSignals.stream.listen(_on);
  }

  final NeonBackend b;
  late final StreamSubscription<CallEnvelope> _signals;
  final _updates = StreamController<CallUpdate>.broadcast();

  static const _ice = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ],
    'sdpSemantics': 'unified-plan',
  };

  /// How long a call rings before it's "no answer".
  static const ringFor = Duration(seconds: 45);

  RTCPeerConnection? _pc;
  MediaStream? _local;
  final local = RTCVideoRenderer();
  final remote = RTCVideoRenderer();
  bool _renderers = false;

  String? _id;
  bool _video = false;
  CallEnvelope? _ringing;
  Timer? _ringOut;
  bool _connected = false;

  @override
  Stream<CallUpdate> get updates => _updates.stream;

  /// The partner's video has frames (tests).
  bool get receivingVideo => remote.videoWidth > 0;

  void _say(CallUpdate u) {
    if (!_updates.isClosed) _updates.add(u);
  }

  Future<void> _ensureRenderers() async {
    if (_renderers) return;
    await local.initialize();
    await remote.initialize();
    _renderers = true;
  }

  Future<RTCPeerConnection> _open({required bool video}) async {
    await _ensureRenderers();
    final pc = await createPeerConnection(_ice);
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': video ? {'facingMode': 'user'} : false,
    });
    _local = stream;
    local.srcObject = video ? stream : null;
    for (final t in stream.getTracks()) {
      await pc.addTrack(t, stream);
    }
    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) remote.srcObject = e.streams.first;
    };
    pc.onConnectionState = (s) {
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _connected = true;
          _ringOut?.cancel();
          _say(const CallUpdate(CallPhase.connected));
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          unawaited(_close(CallEnd.failed, tell: true));
        default:
          break;
      }
    };
    _pc = pc;
    return pc;
  }

  /// The local description once its candidates are in (or after 4 s).
  Future<RTCSessionDescription> _gathered(RTCPeerConnection pc) async {
    final done = Completer<void>();
    if (pc.iceGatheringState ==
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      done.complete();
    }
    pc.onIceGatheringState = (s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !done.isCompleted) {
        done.complete();
      }
    };
    await done.future.timeout(const Duration(seconds: 4), onTimeout: () {});
    return (await pc.getLocalDescription())!;
  }

  @override
  Future<void> dial({required bool video}) async {
    _id = NeonChatRepository.uuid();
    _video = video;
    _connected = false;
    _say(const CallUpdate(CallPhase.ringing));
    try {
      final pc = await _open(video: video);
      await pc.setLocalDescription(await pc.createOffer());
      final offer = await _gathered(pc);
      final sent = await b.post(
        MailKind.call,
        CallEnvelope(
          op: 'offer',
          id: _id!,
          video: video,
          sdp: offer.sdp,
          sdpType: offer.type,
        ),
      );
      if (!sent) return await _close(CallEnd.failed);
      _ringOut = Timer(ringFor, () => unawaited(_close(CallEnd.noAnswer)));
    } on Object {
      await _close(CallEnd.failed);
    }
  }

  @override
  Future<void> answer() async {
    final offer = _ringing;
    if (offer == null) return _close(CallEnd.failed);
    _ringing = null;
    _id = offer.id;
    _video = offer.video;
    _say(const CallUpdate(CallPhase.connecting));
    try {
      final pc = await _open(video: offer.video);
      await pc.setRemoteDescription(
        RTCSessionDescription(offer.sdp, offer.sdpType ?? 'offer'),
      );
      await pc.setLocalDescription(await pc.createAnswer());
      final answer = await _gathered(pc);
      await b.post(
        MailKind.call,
        CallEnvelope(
          op: 'answer',
          id: offer.id,
          video: offer.video,
          sdp: answer.sdp,
          sdpType: answer.type,
        ),
      );
    } on Object {
      await _close(CallEnd.failed, tell: true);
    }
  }

  Future<void> _on(CallEnvelope e) async {
    switch (e.op) {
      case 'offer':
        // Ringing here; CallArrived opens the incoming call page.
        _ringing = e;
      case 'answer' when e.id == _id && _pc != null:
        _say(const CallUpdate(CallPhase.connecting));
        await _pc!.setRemoteDescription(
          RTCSessionDescription(e.sdp, e.sdpType ?? 'answer'),
        );
      case 'decline' when e.id == _id:
        await _close(CallEnd.declined);
      case 'end' when e.id == _id || e.id == _ringing?.id:
        _ringing = null;
        await _close(CallEnd.theyHungUp);
    }
  }

  @override
  Future<void> hangUp() async {
    final ringing = _ringing;
    if (ringing != null) {
      _ringing = null;
      await b.post(MailKind.call, CallEnvelope(op: 'decline', id: ringing.id));
      return _close(CallEnd.declined);
    }
    await _close(CallEnd.hungUp, tell: true);
  }

  Future<void> _close(CallEnd why, {bool tell = false}) async {
    final id = _id;
    if (tell && id != null) {
      await b.post(MailKind.call, CallEnvelope(op: 'end', id: id));
    }
    _ringOut?.cancel();
    _id = null;
    final pc = _pc;
    _pc = null;
    for (final t in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _local?.dispose();
    _local = null;
    if (_renderers) {
      local.srcObject = null;
      remote.srcObject = null;
    }
    await pc?.close();
    _connected = false;
    _say(CallUpdate(CallPhase.ended, why));
  }

  @override
  void mute(bool on) {
    for (final t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !on;
    }
  }

  @override
  void cameraOff(bool off) {
    for (final t in _local?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !off;
    }
  }

  @override
  Future<void> flip() async {
    final tracks = _local?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  @override
  void speaker(bool on) => unawaited(Helper.setSpeakerphoneOn(on));

  @override
  Widget? remoteView() => _connected && _video
      ? RTCVideoView(
          remote,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        )
      : null;

  @override
  Widget? localView() => _video && _local != null
      ? RTCVideoView(
          local,
          mirror: true,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        )
      : null;

  Future<void> dispose() async {
    await _signals.cancel();
    await _updates.close();
    if (_renderers) {
      await local.dispose();
      await remote.dispose();
    }
  }
}
