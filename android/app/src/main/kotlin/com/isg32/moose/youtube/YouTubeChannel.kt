package com.isg32.moose.youtube

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.downloader.Downloader
import org.schabi.newpipe.extractor.downloader.Request
import org.schabi.newpipe.extractor.downloader.Response
import org.schabi.newpipe.extractor.exceptions.ReCaptchaException
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.DeliveryMethod
import org.schabi.newpipe.extractor.stream.StreamInfo
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.math.abs

/**
 * YouTube audio through NewPipe's extractor, the engine NewPipe itself
 * uses. Moose tries it first for a song clip, kept
 * up to date by the NewPipe team when YouTube changes.
 *
 * Methods on `moose/youtube`:
 * - `audio({link, quality})` → {url, mime, bitrate, ms}: an audio-only
 *   stream that plays straight from its URL, picked for `quality`
 *   ("best", "high", "medium" or "low"; see lib/platform/quality.dart).
 */
object YouTubeChannel {
    private const val NAME = "moose/youtube"

    @Volatile
    private var ready = false

    fun register(messenger: BinaryMessenger) {
        val main = Handler(Looper.getMainLooper())
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "audio" -> thread {
                    val reply = try {
                        val link = call.argument<String>("link") ?: error("No link")
                        val quality = call.argument<String>("quality") ?: "best"
                        Result.success(audio(link, quality))
                    } catch (e: Exception) {
                        Result.failure(e)
                    }
                    main.post {
                        reply.fold(
                            { result.success(it) },
                            { result.error("youtube", it.message ?: it.javaClass.simpleName, null) },
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun audio(link: String, quality: String): Map<String, Any?> {
        if (!ready) {
            synchronized(this) {
                if (!ready) {
                    NewPipe.init(OkDownloader)
                    ready = true
                }
            }
        }
        val info = StreamInfo.getInfo(ServiceList.YouTube, link)
        val streams = info.audioStreams
            .filter { it.deliveryMethod == DeliveryMethod.PROGRESSIVE_HTTP && it.isUrl }
        val stream = pick(streams, quality) ?: error("No playable audio stream")
        return mapOf(
            "url" to stream.content,
            "mime" to stream.format?.mimeType,
            "bitrate" to stream.averageBitrate,
            "ms" to info.duration * 1000,
        )
    }

    /** Same rule as the Dart side: best/low are the extremes, high and
     *  medium the stream closest to 160 and 128 kbps; M4A wins ties. */
    private fun pick(streams: List<AudioStream>, quality: String): AudioStream? {
        if (streams.isEmpty()) return null
        val m4aFirst = compareByDescending<AudioStream> { it.format?.mimeType == "audio/mp4" }
        return when (quality) {
            "low" -> streams.sortedWith(compareBy<AudioStream> { it.averageBitrate }.then(m4aFirst))
            "high", "medium" -> {
                val target = if (quality == "high") 160 else 128
                streams.sortedWith(compareBy<AudioStream> { abs(it.averageBitrate - target) }.then(m4aFirst))
            }
            else -> streams.sortedWith(compareByDescending<AudioStream> { it.averageBitrate }.then(m4aFirst))
        }.firstOrNull()
    }

    /** NewPipe's HTTP calls, over OkHttp (as in NewPipe's DownloaderImpl). */
    private object OkDownloader : Downloader() {
        private const val USER_AGENT =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"

        private val client = OkHttpClient.Builder()
            .readTimeout(30, TimeUnit.SECONDS)
            .build()

        override fun execute(request: Request): Response {
            val body = request.dataToSend()?.toRequestBody()
            val builder = okhttp3.Request.Builder()
                .method(request.httpMethod(), body)
                .url(request.url())
                .addHeader("User-Agent", USER_AGENT)
            request.headers().forEach { (name, values) ->
                builder.removeHeader(name)
                values.forEach { builder.addHeader(name, it) }
            }
            client.newCall(builder.build()).execute().use { response ->
                if (response.code == 429) {
                    throw ReCaptchaException("reCaptcha challenge requested", request.url())
                }
                return Response(
                    response.code,
                    response.message,
                    response.headers.toMultimap(),
                    response.body?.string(),
                    response.request.url.toString(),
                )
            }
        }
    }
}
