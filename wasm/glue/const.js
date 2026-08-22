// =============================================================================
// asx/wasm/glue.js - WASM UI renderer + SPA navigation
// =============================================================================
// Served at /_asx/glue.js by the framework (asx/wasm/glue.asm).
// Instantiates the page's WASM module, hydrates the SSR DOM (or falls
// back to CSR), wires up mouse/keyboard events, hot reload, and -- SPA
// navigation: clicking an <a> link inside #ui fetches the target route's
// SSR HTML, swaps the DOM, instantiates the new WASM module, and pushes
// history state. Hovering a link pre-fetches its wasm module.
//
// Phase machine: SSR -> HYDRATING -> INTERACTIVE (per mount).
//
// NOTE: this file is ONE of seven modules (const.js, state.js, mount.js,
// shell.js, spa.js, overlay.js, boot.js) that glue.asm embeds with
// consecutive incbins - nasm concatenates them at assembly time, so there
// is no generated glue.js bundle file. The ORDER is fixed in glue.asm.
// Edit any module freely; `make` rebuilds the glue.o when one changes.
// =============================================================================

const TAG_NAMES = ["div","main","div","section","nav","header","footer","article","aside","figure","blockquote","ul","ol","li","form","table","thead","tbody","tfoot","tr","td","th","details","dialog","video","audio","picture","iframe","canvas","select","textarea","fieldset","dl","dt","dd","menu","hgroup","h1","h2","h3","h4","h5","h6","p","span","a","label","strong","em","code","pre","small","b","i","u","mark","time","cite","q","abbr","sub","sup","kbd","samp","var","del","ins","s","option","figcaption","legend","caption","summary","button","img","input","br","hr","source","meta","link","area","base","col","embed","track","wbr"];
const TPROP = ["","","none","all","color,background-color,border-color,outline-color,text-decoration-color,fill,stroke,--tw-gradient-from,--tw-gradient-via,--tw-gradient-to","opacity","box-shadow","transform,translate,scale,rotate"];
const TEASE = ["","linear","cubic-bezier(0.4,0,1,1)","cubic-bezier(0,0,0.2,1)","cubic-bezier(0.4,0,0.2,1)"];
const STRETCH = ["","ultra-condensed","extra-condensed","condensed","semi-condensed","normal","semi-expanded","expanded","extra-expanded","ultra-expanded"];
const VARNUM = ["","normal","ordinal","slashed-zero","lining-nums","oldstyle-nums","proportional-nums","tabular-nums","diagonal-fractions","stacked-fractions"];
const TRACK = ["","-0.05em","-0.025em","0em","0.025em","0.05em","0.1em"];
const LEAD = ["","1","1.25","1.375","1.5","1.625","2","0.75rem","1rem","1.25rem","1.5rem","1.75rem","2rem","2.25rem","2.5rem"];
const WS = ["","normal","nowrap","pre","pre-line","pre-wrap","break-spaces"];
const WB = ["","normal","break-word","break-all","keep-all"];
const OW = ["","","","","","normal","break-word","anywhere"];
const VALIGN = ["","normal","top","middle","bottom","text-top","text-bottom","sub","super"];
const DSTYLE = ["","solid","double","dotted","dashed","wavy"];
const TW = ["","wrap","nowrap","balance","pretty"];
const HYPHENS = ["","none","manual","auto"];
const ANIM = ["","spin 1s linear infinite","ping 1s cubic-bezier(0,0,0.2,1) infinite","pulse 2s cubic-bezier(0.4,0,0.6,1) infinite","bounce 1s infinite"];
const FAM = ["","ui-sans-serif,system-ui,sans-serif,\"Apple Color Emoji\",\"Segoe UI Emoji\",\"Segoe UI Symbol\",\"Noto Color Emoji\"","ui-serif,Georgia,Cambria,\"Times New Roman\",Times,serif","ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,\"Liberation Mono\",\"Courier New\",monospace"];

const tagFor = (type, tagId) => tagId ? (TAG_NAMES[tagId] || "DIV").toUpperCase() : (type === 1 ? "SPAN" : type === 2 ? "CANVAS" : "DIV");
const hex = (v) => "#"+((v>>16)&255).toString(16).padStart(2,"0")+((v>>8)&255).toString(16).padStart(2,"0")+(v&255).toString(16).padStart(2,"0");
