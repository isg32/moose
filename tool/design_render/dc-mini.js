// A tiny stand-in for the Claude Design runtime: enough of the .dc.html
// format (holes, sc-for, sc-if, helmet, renderVals) to render a static board.
class DCLogic { constructor(p) { this.props = p; this.state = {}; } setState(s) { Object.assign(this.state, s); } forceUpdate() {} }
const HOLE = /\{\{\s*([^}]+?)\s*\}\}/g, WHOLE = /^\{\{\s*([^}]+?)\s*\}\}$/;
function resolve(path, scope) {
  if (path === 'true') return true; if (path === 'false') return false;
  if (/^-?\d+(\.\d+)?$/.test(path)) return Number(path);
  if (/^['"].*['"]$/.test(path)) return path.slice(1, -1);
  let v = scope; for (const part of path.split('.')) { if (v == null) return undefined; v = v[part]; } return v;
}
const str = (t, scope) => t.replace(HOLE, (_, p) => { const v = resolve(p, scope); return v == null ? '' : String(v); });
function renderChildren(src, scope, parent) { for (const c of [...src.childNodes]) renderNode(c, scope, parent); }
function renderNode(n, scope, parent) {
  if (n.nodeType === 3) { parent.appendChild(document.createTextNode(str(n.textContent, scope))); return; }
  if (n.nodeType !== 1) return;
  const tag = n.localName;
  if (tag === 'sc-for') {
    const list = resolve(n.getAttribute('list').match(WHOLE)[1], scope) || [], as = n.getAttribute('as');
    list.forEach((it, i) => { const s = Object.create(scope); s[as] = it; s.$index = i; renderChildren(n, s, parent); });
    return;
  }
  if (tag === 'sc-if') { if (resolve(n.getAttribute('value').match(WHOLE)[1], scope)) renderChildren(n, scope, parent); return; }
  if (tag === 'dc-import' || tag === 'script') return;
  const el = n.cloneNode(false);
  for (const a of [...n.attributes]) {
    if (/^on[A-Z]/.test(a.name) || a.name.startsWith('hint-')) { el.removeAttribute(a.name); continue; }
    if (!a.value.includes('{{')) continue;
    const w = a.value.match(WHOLE);
    const v = w ? resolve(w[1], scope) : str(a.value, scope);
    if (typeof v === 'function' || v == null) el.removeAttribute(a.name); else el.setAttribute(a.name, String(v));
  }
  renderChildren(n, scope, el); parent.appendChild(el);
}
document.addEventListener('DOMContentLoaded', () => {
  const sc = document.querySelector('script[data-dc-script]');
  const meta = JSON.parse(sc.getAttribute('data-props') || '{}'), props = {};
  for (const k in meta) if (meta[k] && 'default' in meta[k]) props[k] = meta[k].default;
  const Component = new Function('DCLogic', sc.textContent + '\nreturn Component;')(DCLogic);
  const vals = new Component(props).renderVals();
  const root = document.querySelector('x-dc');
  const helmet = root.querySelector('helmet');
  if (helmet) { for (const c of [...helmet.children]) document.head.appendChild(c); helmet.remove(); }
  const frag = document.createDocumentFragment();
  renderChildren(root, vals, frag);
  root.replaceWith(frag);
  document.title = 'rendered';
});
