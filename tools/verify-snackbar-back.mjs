import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url),ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const text=fs.readFileSync('entry/src/main/ets/pages/Index.ets','utf8').replace('struct Index','class Index');
const tree=ts.createSourceFile('index.ts',text,ts.ScriptTarget.Latest,true),cls=tree.statements.find(ts.isClassDeclaration);
const methods=['notify','onBackPress','backFromBookManagement'].map(name=>cls.members.find(m=>ts.isMethodDeclaration(m)&&m.name.getText(tree)===name).getText(tree)).join('\n');
let style,dismissed=0,loads=0;
class HdsSnackBar{dismiss(){dismissed++;}show(a,b,c,s){style=s;}}
const context={exports:{},HdsSnackBar,SnackBarOperationType:{CLOSE_BUTTON_ONLY:1}};
vm.runInNewContext(ts.transpileModule('class Page{'+methods+'}exports.Page=Page;',{compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText,context);
const p=new context.exports.Page();Object.assign(p,{getUIContext:()=>({getFocusController:()=>({clearFocus(){}})}),dismissPrepaidNotice(){},loadLedger(){loads++;},showBookManagement:true,bookManagement:true,bookBusy:false});
p.notify('删除成功');assert.equal(style.duration,3000);style.pressBackCallback();assert.equal(p.showBookManagement,false);assert.equal(loads,1);assert.equal(dismissed,2);
p.showBookManagement=true;p.bookEditing=true;p.notify('提示');style.pressBackCallback();assert.equal(p.bookEditing,false);assert.equal(p.showBookManagement,true);
p.bookBusy=true;p.notify('提示');style.pressBackCallback();assert.equal(p.showBookManagement,true);
p.bookBusy=false;p.showBookManagement=false;p.notify('提示');style.pressBackCallback();assert.equal(p.showBookManagement,false);
console.log('PASS production SnackBar back callback: management returns, editor returns to list, busy guard preserved, root dismisses only');
