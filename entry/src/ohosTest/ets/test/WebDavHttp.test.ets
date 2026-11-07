import { util } from '@kit.ArkTS';
import { describe, expect, it } from '@ohos/hypium';
import { NativeDavTransport } from '../../../main/ets/data/webdav/WebDavClient';

/** Explicit integration suite. Requires tools/serve-webdav-fixture.py and hdc reverse forwarding.
 * Production WebDavClient still enforces HTTPS; only this adapter test uses loopback HTTP.
 */
export default function webDavHttpTest() {
  describe('WebDavHttp', () => {
    it('native_custom_method_binary_headers_and_redirect', 0, async () => {
      const transport = new NativeDavTransport();
      const base = 'http://127.0.0.1:18765';
      const auth = 'Basic Zml4dHVyZTpmaXh0dXJl';
      const folder = base + '/dav/fixture-' + util.generateRandomUUID() + '/';
      expect((await transport.send(folder, 'MKCOL', auth, '', 1024)).status).assertEqual(201);
      expect((await transport.send(folder, 'MKCOL', auth, '', 1024)).status).assertEqual(405);
      const target = folder + 'xiaoqiao-fixture.xqbackup';
      const data = new Uint8Array([0, 1, 255, 128, 13, 10, 0, 99]).buffer as ArrayBuffer;
      expect((await transport.send(target, 'PUT', auth, data, 1024)).status).assertEqual(201);
      expect((await transport.send(target, 'PUT', auth, data, 1024)).status).assertEqual(412);
      const list = await transport.send(folder, 'PROPFIND', auth, '<propfind/>', 1024 * 1024);
      expect(list.status).assertEqual(207);
      expect(util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(list.body)).includes(target.slice(base.length))).assertTrue();
      const fetched = await transport.send(target, 'GET', auth, '', 1024);
      expect(fetched.status).assertEqual(200);
      expect(Array.from(new Uint8Array(fetched.body)).join(',')).assertEqual('0,1,255,128,13,10,0,99');
      expect((await transport.send(target, 'GET', 'Basic invalid-fixture', '', 1024)).status).assertEqual(401);
      let redirectRejected = false;
      try { redirectRejected = (await transport.send(base + '/redirect', 'GET', auth, '', 1024)).status === 302; }
      catch (_) { redirectRejected = true; }
      expect(redirectRejected).assertTrue();
    });
  });
}
