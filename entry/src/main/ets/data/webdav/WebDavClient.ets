import { http } from '@kit.NetworkKit';
import { url, util, xml } from '@kit.ArkTS';

export const DAV_MAX_BYTES: number = 32 * 1024 * 1024;
export interface DavConfig { endpoint: string; username: string; password: string; }
export interface DavFile { href: string; name: string; bytes: number; modified: string; }
export interface DavListing { directory: boolean; files: DavFile[]; }
export interface DavResponse { status: number; body: ArrayBuffer; }
export interface DavTransport {
  send(target: string, method: string, authorization: string, body: ArrayBuffer | string, limit: number): Promise<DavResponse>;
}

interface DavHeaders { Authorization: string; Depth: string; 'Content-Type': string; 'If-None-Match'?: string; }

export class NativeDavTransport implements DavTransport {
  async send(target: string, method: string, authorization: string, body: ArrayBuffer | string, limit: number): Promise<DavResponse> {
    const request = http.createHttp();
    try {
      const headers: DavHeaders = method === 'PUT' ?
        { Authorization: authorization, Depth: '1', 'Content-Type': 'application/octet-stream', 'If-None-Match': '*' } :
        { Authorization: authorization, Depth: '1', 'Content-Type': method === 'PROPFIND' ? 'application/xml; charset=utf-8' : 'application/octet-stream' };
      const options: http.HttpRequestOptions = {
        method: method === 'PUT' ? http.RequestMethod.PUT : method === 'PROPFIND' ? http.RequestMethod.POST : http.RequestMethod.GET, customMethod: method,
        header: headers, expectDataType: http.HttpDataType.ARRAY_BUFFER, usingCache: false,
        connectTimeout: 15000, readTimeout: 60000, maxRedirects: 0, maxLimit: limit };
      if (body instanceof ArrayBuffer || body.length > 0) { options.extraData = body; }
      const response = await request.request(target, options);
      const result = response.result === '' || response.result === undefined || response.result === null ? new ArrayBuffer(0) : response.result as ArrayBuffer;
      if (!(result instanceof ArrayBuffer) || result.byteLength > limit) { throw new Error('DAV_SIZE'); }
      return { status: response.responseCode, body: result };
    } finally { request.destroy(); }
  }
}

export function normalizedDav(config: DavConfig): DavConfig {
  const endpoint = config.endpoint.trim();
  if (endpoint.length > 2048 || /[\s\\\u0000-\u001f]/.test(endpoint)) { throw new Error('DAV_CONFIG'); }
  let parsed: url.URL;
  try { parsed = new url.URL(endpoint); } catch (_) { throw new Error('DAV_CONFIG'); }
  if (parsed.protocol !== 'https:' || parsed.username.length > 0 || parsed.password.length > 0 ||
    parsed.search.length > 0 || parsed.hash.length > 0 || parsed.hostname.length === 0 ||
    config.username.length === 0 || config.username.length > 512 || /[:\r\n]/.test(config.username) ||
    config.password.length === 0 || config.password.length > 4096) { throw new Error('DAV_CONFIG'); }
  parsed.pathname = parsed.pathname.endsWith('/') ? parsed.pathname : parsed.pathname + '/';
  const value: DavConfig = { endpoint: parsed.toString(), username: config.username, password: config.password };
  if (new util.TextEncoder().encodeInto(JSON.stringify(value)).length > 1024) { throw new Error('DAV_CREDENTIAL_SIZE'); }
  return value;
}

function davTarget(endpoint: string, href: string): string {
  if (/[\\\u0000-\u0020]/.test(href)) { throw new Error('DAV_PATH'); }
  const base = new url.URL(endpoint);
  const target = new url.URL(href, base.toString());
  if (target.origin !== base.origin || target.username.length > 0 || target.password.length > 0 ||
    target.search.length > 0 || target.hash.length > 0 || !target.pathname.startsWith(base.pathname)) { throw new Error('DAV_PATH'); }
  const remainder = target.pathname.slice(base.pathname.length);
  const decoded = decodeURIComponent(remainder);
  if (decoded.length === 0 || decoded.includes('/') || decoded.includes('\\') || decoded === '..' || /[\u0000-\u001f]/.test(decoded)) {
    throw new Error('DAV_PATH');
  }
  return target.toString();
}

/** Parse only successful DAV properties. Never resolve external entities or follow arbitrary hrefs. */
export function parseDavListing(body: ArrayBuffer, endpoint: string): DavListing {
  const text = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(body));
  if (/<!DOCTYPE|<!ENTITY/i.test(text)) { throw new Error('DAV_XML'); }
  const files: DavFile[] = [];
  let path: string[] = [];
  let texts: string[] = [];
  let href = '', size = '', modified = '', status = '';
  let propSize = '', propModified = '';
  let propCollection = false;
  let collection = false, success = false, root = false, directory = false;
  const parser = new xml.XmlPullParser(body, 'UTF-8');
  parser.parseXml({ supportDoctype: false, ignoreNameSpace: false,
    tokenValueCallbackFunction: (event: xml.EventType, info: xml.ParseInfo): boolean => {
      if (event === xml.EventType.START_TAG) {
        const name = info.getNamespace() === 'DAV:' ? info.getName().split(':').pop() || '' : '_';
        path.push(name); texts.push('');
        if (path.length === 1) { root = name === 'multistatus'; }
        if (name === 'response') { href = ''; size = ''; modified = ''; success = false; collection = false; }
        if (name === 'propstat') { status = ''; propSize = ''; propModified = ''; propCollection = false; }
        if (name === 'collection' && path.includes('propstat')) { propCollection = true; }
      } else if (event === xml.EventType.TEXT || event === xml.EventType.CDSECT) {
        if (texts.length > 0) { texts[texts.length - 1] += info.getText(); }
      } else if (event === xml.EventType.END_TAG) {
        const name = path.pop() || '';
        const value = (texts.pop() || '').trim();
        if (name === 'href' && path[path.length - 1] === 'response') { href = value; }
        if (name === 'getcontentlength' && path[path.length - 1] === 'prop') { propSize = value; }
        if (name === 'getlastmodified' && path[path.length - 1] === 'prop') { propModified = value; }
        if (name === 'status') { status = value; }
        if (name === 'propstat' && /^HTTP\/\S+ 200(?:\s|$)/.test(status)) {
          success = true; if (propSize.length > 0) { size = propSize; }
          if (propModified.length > 0) { modified = propModified; } collection = collection || propCollection;
        }
        if (name === 'response' && success && collection) {
          try {
            const target = new url.URL(href, endpoint);
            const base = new url.URL(endpoint);
            if (target.origin === base.origin && target.search.length === 0 && target.hash.length === 0 &&
              target.username.length === 0 && target.password.length === 0 &&
              target.pathname.replace(/\/$/, '') === base.pathname.replace(/\/$/, '')) { directory = true; }
          } catch (_) { /* A foreign or malformed collection cannot validate our directory. */ }
        }
        if (name === 'response' && success && !collection) {
          try {
            const target = davTarget(endpoint, href);
            const name = decodeURIComponent(new url.URL(target).pathname.split('/').pop() || '');
            const bytes = /^\d+$/.test(size) ? Number(size) : 0;
            if (name.startsWith('xiaoqiao-') && name.endsWith('.xqbackup') && Number.isSafeInteger(bytes) && bytes > 0 && bytes <= DAV_MAX_BYTES &&
              !files.some((file: DavFile) => file.href === target)) { files.push({ href: target, name: name, bytes: bytes, modified: modified }); }
          } catch (_) { /* Ignore directories, unrelated files and untrusted hrefs. */ }
        }
      }
      return true;
    } });
  if (!root || path.length !== 0) { throw new Error('DAV_XML'); }
  return { directory: directory, files: files.sort((a: DavFile, b: DavFile) => b.name.localeCompare(a.name)) };
}

export function parseDavFiles(body: ArrayBuffer, endpoint: string): DavFile[] {
  return parseDavListing(body, endpoint).files;
}

export class WebDavClient {
  private readonly config: DavConfig;
  private readonly transport: DavTransport;
  constructor(config: DavConfig, transport: DavTransport = new NativeDavTransport()) {
    const parent = normalizedDav(config);
    this.config = { endpoint: parent.endpoint + 'xiaoqiao/', username: parent.username, password: parent.password };
    this.transport = transport;
  }
  private authorization(): string {
    const bytes = new util.TextEncoder().encodeInto(this.config.username + ':' + this.config.password);
    return 'Basic ' + new util.Base64Helper().encodeToStringSync(bytes);
  }
  private async send(target: string, method: string, body: ArrayBuffer | string, limit: number): Promise<DavResponse> {
    const response = await this.transport.send(target, method, this.authorization(), body, limit);
    if (response.body.byteLength > limit) { throw new Error('DAV_SIZE'); }
    if (response.status === 401 || response.status === 403) { throw new Error('DAV_AUTH'); }
    if (response.status >= 300 && response.status < 400) { throw new Error('DAV_REDIRECT'); }
    return response;
  }
  private async directory(): Promise<DavListing> {
    const request = '<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:resourcetype/><d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>';
    let response = await this.send(this.config.endpoint, 'PROPFIND', request, 1024 * 1024);
    if (response.status === 404) {
      const created = await this.send(this.config.endpoint, 'MKCOL', '', 1024 * 1024);
      // 405 may mean another device created the directory after our initial check.
      if (created.status !== 201 && created.status !== 405) { throw new Error('DAV_CREATE_DIRECTORY'); }
      response = await this.send(this.config.endpoint, 'PROPFIND', request, 1024 * 1024);
    }
    if (response.status !== 207) { throw new Error('DAV_DIRECTORY'); }
    const listing = parseDavListing(response.body, this.config.endpoint);
    if (!listing.directory) { throw new Error('DAV_DIRECTORY'); }
    return listing;
  }
  async list(): Promise<DavFile[]> { return (await this.directory()).files; }
  async upload(name: string, body: ArrayBuffer): Promise<void> {
    if (!/^xiaoqiao-[a-zA-Z0-9-]+\.xqbackup$/.test(name) || body.byteLength === 0 || body.byteLength > DAV_MAX_BYTES) { throw new Error('DAV_SIZE'); }
    await this.directory();
    const response = await this.send(davTarget(this.config.endpoint, name), 'PUT', body, 1024 * 1024);
    if (response.status !== 201) { throw new Error(response.status === 412 ? 'DAV_EXISTS' : 'DAV_UPLOAD'); }
  }
  async download(file: DavFile): Promise<ArrayBuffer> {
    if (file.bytes <= 0 || file.bytes > DAV_MAX_BYTES) { throw new Error('DAV_SIZE'); }
    const response = await this.send(davTarget(this.config.endpoint, file.href), 'GET', '', DAV_MAX_BYTES);
    if (response.status !== 200 || response.body.byteLength !== file.bytes) { throw new Error('DAV_DOWNLOAD'); }
    return response.body;
  }
}

export function davMessage(error: Error): string {
  switch (error.message) {
    case 'DAV_CONFIG': return '请填写有效的 HTTPS 文件夹地址、用户名和密码。';
    case 'DAV_CREDENTIAL_SIZE': return '连接信息合计不能超过 1024 字节，请缩短地址或使用应用密码。';
    case 'DAV_AUTH': return '认证失败或没有访问权限，请检查账号和应用密码。';
    case 'DAV_REDIRECT': return '服务器发生重定向，请填写最终 HTTPS 文件夹地址。';
    case 'DAV_DIRECTORY': return '无法读取 xiaoqiao 文件夹，请检查父目录地址、权限及同名项是否为文件。';
    case 'DAV_CREATE_DIRECTORY': return '无法创建 xiaoqiao 文件夹，请确认父目录存在并允许创建目录。';
    case 'DAV_SIZE': return '此备份超出 WebDAV 支持的 32 MiB 上限，请减少资源体积后重试。';
    case 'DAV_EXISTS': return '远端已存在同名文件，请重试生成新的备份。';
    default: return '操作未完成，请检查网络、服务器和备份文件后重试。';
  }
}
