import { BackupFiles } from '../../../main/ets/data/backup/BackupFiles';
import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { abilityDelegatorRegistry, Driver, ON } from '@kit.TestKit';
import { describe, expect, it } from '@ohos/hypium';
import { DavCredentials } from '../../../main/ets/data/webdav/DavCredentials';
import { DavConfig, DavResponse, DavTransport, normalizedDav, parseDavFiles, WebDavClient } from '../../../main/ets/data/webdav/WebDavClient';
import { WebDavBackup } from '../../../main/ets/data/webdav/WebDavBackup';
import { LedgerWorkspace } from '../../../main/ets/data/rdb/LedgerWorkspace';

function workspacePath(host: common.Context, name: string): string { return host.filesDir + '/ledger_assets/' + name.slice(0, -3); }
const config: DavConfig = { endpoint: 'https://example.invalid/dav/', username: 'test', password: 'fixture-only' };
function bytes(text: string): ArrayBuffer { return new util.TextEncoder().encodeInto(text).buffer as ArrayBuffer; }
function response(href: string, size: string = '100', code: string = '200 OK'): string {
  return `<d:response><d:href>${href}</d:href><d:propstat><d:prop><d:getcontentlength>${size}</d:getcontentlength><d:resourcetype/></d:prop><d:status>HTTP/1.1 ${code}</d:status></d:propstat></d:response>`;
}
function multi(content: string): ArrayBuffer { return bytes('<d:multistatus xmlns:d="DAV:">' + content + '</d:multistatus>'); }
async function rejected(run: () => Promise<void>): Promise<void> {
  let failed = false; try { await run(); } catch (_) { failed = true; } expect(failed).assertTrue();
}
class FakeDav implements DavTransport {
  data: ArrayBuffer = new ArrayBuffer(0);
  file: string = '';
  calls: string[] = [];
  status: number = 0;
  exists: boolean = false;
  collection: boolean = true;
  createStatus: number = 201;
  async send(target: string, method: string, authorization: string, body: ArrayBuffer | string, limit: number): Promise<DavResponse> {
    this.calls.push(method);
    expect(authorization.startsWith('Basic ')).assertTrue();
    expect(target.startsWith(config.endpoint)).assertTrue();
    expect(limit > 0).assertTrue();
    if (this.status !== 0) { return { status: this.status, body: new ArrayBuffer(0) }; }
    if (method === 'MKCOL') { this.exists = this.createStatus === 201 || this.createStatus === 405; return { status: this.createStatus, body: new ArrayBuffer(0) }; }
    if (method === 'PROPFIND' && !this.exists) { return { status: 404, body: new ArrayBuffer(0) }; }
    if (method === 'PUT') { this.data = body as ArrayBuffer; this.file = target; return { status: 201, body: new ArrayBuffer(0) }; }
    if (method === 'GET') { return { status: 200, body: this.data }; }
    const type = this.collection ? '<d:collection/>' : '';
    return { status: 207, body: multi('<d:response><d:href>/dav/xiaoqiao/</d:href><d:propstat><d:prop><d:resourcetype>' + type + '</d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>' + (this.file.length === 0 ? '' : response(this.file, this.data.byteLength.toString()))) };
  }
}

export default function webDavTest() {
  describe('WebDav', () => {
    it('validates_configuration_and_namespaced_multistatus', 0, async () => {
      expect(normalizedDav({ endpoint: 'https://example.invalid/dav', username: 'a', password: 'b' }).endpoint).assertEqual(config.endpoint);
      for (const endpoint of ['', 'invalid', 'http://example.invalid/dav/', 'https://user:pass@example.invalid/dav/', 'https://example.invalid/dav/?a=1', 'https://example.invalid/dav/#x']) {
        await rejected(async () => { normalizedDav({ endpoint: endpoint, username: 'a', password: 'b' }); });
      }
      await rejected(async () => { normalizedDav({ endpoint: config.endpoint, username: 'a', password: '密'.repeat(400) }); });
      const extra = '<d:response><d:href>/dav/xiaoqiao-mixed.xqbackup</d:href>' +
        '<d:propstat><d:prop><d:getcontentlength>120</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>' +
        '<d:propstat><d:prop><d:getcontentlength>0</d:getcontentlength></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat></d:response>';
      const files = parseDavFiles(multi(response('/dav/xiaoqiao-valid.xqbackup') + response('https://evil.invalid/xiaoqiao-other.xqbackup') +
        response('/other/xiaoqiao-wrong.xqbackup') + response('/dav/sub/xiaoqiao-nested.xqbackup') + response('/dav/xiaoqiao-escape%2f.xqbackup') +
        response('/dav/xiaoqiao-bad.xqbackup', '0') + response('/dav/xiaoqiao-denied.xqbackup', '100', '403 Forbidden') + extra), config.endpoint);
      expect(files.length).assertEqual(2);
      expect(files.find(file => file.name === 'xiaoqiao-mixed.xqbackup')?.bytes).assertEqual(120);
      const defaultNs = '<multistatus xmlns="DAV:"><response><href>/dav/xiaoqiao-default.xqbackup</href><propstat><prop><getcontentlength>20</getcontentlength></prop><status>HTTP/1.1 200 OK</status></propstat></response></multistatus>';
      expect(parseDavFiles(bytes(defaultNs), config.endpoint).length).assertEqual(1);
      await rejected(async () => { parseDavFiles(bytes('<!DOCTYPE foo [<!ENTITY x SYSTEM "file:///data/private">]><foo/>'), config.endpoint); });
      await rejected(async () => { parseDavFiles(bytes('<invalid/>'), config.endpoint); });
    });
    it('rejects_auth_redirect_collisions_and_download_mismatch', 0, async () => {
      const transport = new FakeDav(); const client = new WebDavClient(config, transport);
      for (const status of [401, 403, 302, 404, 500]) { transport.status = status; await rejected(async () => { await client.list(); }); }
      transport.status = 412;
      await rejected(async () => { await client.upload('xiaoqiao-fixture.xqbackup', bytes('data')); });
      transport.status = 0;
      await client.upload('xiaoqiao-fixture.xqbackup', bytes('data'));
      const file = (await client.list())[0];
      expect((await client.download(file)).byteLength).assertEqual(4);
      await rejected(async () => { await client.download({ href: file.href, name: file.name, bytes: 5, modified: '' }); });
      const before = transport.calls.length;
      await rejected(async () => { await client.download({ href: 'https://evil.invalid/a.xqbackup', name: 'a', bytes: 4, modified: '' }); });
      expect(transport.calls.length).assertEqual(before);
    });
    it('creates_xiaoqiao_once_and_rechecks_existing_directory_or_race', 0, async () => {
      const fresh = new FakeDav(); const client = new WebDavClient(config, fresh);
      await client.list(); await client.list();
      expect(fresh.calls.filter((method: string) => method === 'MKCOL').length).assertEqual(1);
      const raced = new FakeDav(); raced.createStatus = 405;
      expect((await new WebDavClient(config, raced).list()).length).assertEqual(0);
      const notDirectory = new FakeDav(); notDirectory.exists = true; notDirectory.collection = false;
      await rejected(async () => { await new WebDavClient(config, notDirectory).list(); });
      expect(notDirectory.calls.includes('MKCOL')).assertFalse();
      const denied = new FakeDav(); denied.createStatus = 403;
      await rejected(async () => { await new WebDavClient(config, denied).list(); });
    });
    it('secure_credentials_round_trip_and_replace', 0, async () => {
      const credentials = new DavCredentials('xiaoqiao.test.' + util.generateRandomUUID());
      try {
        expect(await credentials.load()).assertUndefined();
        await credentials.save(config);
        expect((await credentials.load())?.endpoint).assertEqual(config.endpoint);
        await credentials.save({ endpoint: config.endpoint, username: 'new', password: 'new-fixture-only' });
        expect((await credentials.load())?.username).assertEqual('new');
      } finally { await credentials.remove(); }
      expect(await credentials.load()).assertUndefined();
    });
    it('round_trip_uses_staged_validation_and_keeps_old_ledger_until_confirm', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
      const driver = Driver.create(); await driver.waitForComponent(ON.id('ledger-tab-4'), 10000);
      const host: common.Context = (await delegator.getCurrentTopAbility()).context;
      const name = 'xiaoqiao_app_test_dav_' + util.generateRandomUUID() + '.db';
      try {
        const workspace = await LedgerWorkspace.open(host, name);
        await workspace.setMonthlyBudget('2026-11', '3000');
        const transport = new FakeDav(); const client = new WebDavClient(config, transport);
        const backup = new WebDavBackup(host, workspace.backup, config, client);
        await backup.upload();
        expect(transport.calls.filter((method: string) => method === 'MKCOL').length).assertEqual(1);
        expect(transport.file.startsWith(config.endpoint + 'xiaoqiao/')).assertTrue();
        await workspace.setMonthlyBudget('2026-11', '4000');
        const file = (await backup.list())[0];
        expect(transport.calls.filter((method: string) => method === 'MKCOL').length).assertEqual(1);
        const preview = await backup.prepare(file);
        expect(preview.books).assertEqual(1);
        expect((await workspace.snapshot('2026-11')).budgetTotalMinor).assertEqual('400000');
        await workspace.backup.restore();
        expect((await workspace.snapshot('2026-11')).budgetTotalMinor).assertEqual('300000');
        transport.data = bytes('not a database');
        await rejected(async () => { await backup.prepare((await backup.list())[0]); });
        expect((await workspace.snapshot('2026-11')).budgetTotalMinor).assertEqual('300000');
      } finally {
        await LedgerWorkspace.close(name); await relationalStore.deleteRdbStore(host, name);
        await BackupFiles.remove(workspacePath(host, name));
        for (const folder of ['_stage', '_work', '_previous']) {
          await BackupFiles.remove(host.filesDir + '/ledger_backup/' + name.slice(0, -3) + '_package' + folder);
        }
        for (const suffix of ['_pending.db', '_previous.db', '_candidate.db', '_export.db', '_rollback_work.db']) {
          const path = host.databaseDir + '/rdb/' + name.slice(0, -3) + '_local_backup' + suffix;
          if (await fs.access(path)) { await fs.unlink(path); }
        }
      }
    });
    it('settings_exposes_webdav_controls_without_network_requests', 0, async () => {
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: 'cn.oicode.xiaoqiao', abilityName: 'EntryAbility' });
      const driver = Driver.create(); await driver.waitForComponent(ON.id('ledger-tab-4'), 10000);
      await (await driver.findComponent(ON.id('ledger-tab-4'))).click();
      await driver.waitForComponent(ON.id('local-backup-page'), 5000);
      const page = await (await driver.findComponent(ON.id('local-backup-page'))).getBounds();
      await driver.swipe(page.right - 100, page.bottom - 600,
        page.right - 100, page.top + 300, 800);
      const host = (await delegator.getCurrentTopAbility()).context;
      expect(await driver.findComponent(ON.id('dav-upload')) !== null).assertTrue();
      expect(await driver.waitForComponent(ON.id('dav-upload').enabled(true), 5000) !== null).assertTrue();
      expect(await driver.findComponent(ON.id('dav-endpoint')) !== null).assertTrue();
      expect(await driver.findComponent(ON.id('dav-list')) !== null).assertTrue();
      expect(await driver.screenCap(host.filesDir + '/xiaoqiao-webdav-settings.png')).assertTrue();
      await (await driver.findComponent(ON.id('ledger-tab-0'))).click();
    });
  });
}
