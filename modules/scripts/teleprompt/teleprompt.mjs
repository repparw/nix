#!/usr/bin/env node
import {execFileSync, spawn} from 'node:child_process';
const msg=(...args)=>execFileSync('niri',['msg',...args],{encoding:'utf8'});
const windows=()=>JSON.parse(msg('-j','windows'));
const action=(name,id,...args)=>msg('action',name,'--id',String(id),...args);
const args=process.argv.slice(2);
if(args.includes('--help')){console.log('teleprompt [URL | executable [args...]]\nNo arguments: local script editor and manual scrolling. Window controls require focus.');process.exit(0)}
const before=new Set(windows().map(w=>w.id));
let command;
if(!args.length)command=['helium',`--app=${new URL('./index.html',import.meta.url).href}`,'--new-window'];
else if(/^https?:\/\//.test(args[0]))command=['helium',`--app=${args[0]}`,'--new-window'];
else command=args;
const child=spawn(command[0],command.slice(1),{stdio:'ignore',detached:true});
child.on('error',e=>{console.error(e.message);process.exit(1)});child.unref();
let found;
for(let i=0;i<100;i++){
 await new Promise(r=>setTimeout(r,100));
 const added=windows().filter(w=>!before.has(w.id));
 if(added.length>1)throw new Error('Multiple new windows; refusing to move an ambiguous target');
 if(added.length===1){found=added[0];break}
}
if(!found)throw new Error('No NEW window appeared within 10 seconds. Use an app command that creates a new window.');
const id=found.id;
action('move-window-to-floating',id);action('move-window-to-monitor',id,'DP-1');
action('set-window-width',id,'720');action('set-window-height',id,'180');
action('move-floating-window',id,'--x','600','--y','12');
console.log(`Teleprompt window ${id}: DP-1, 720x180 at 600,12. Use a maximized recording window; fullscreen can cover floating windows. Camera-only capture excludes the desktop; screen sharing may include this prompt.`);
