import fs from "node:fs";
import path from "node:path";

const STATUS_COLORS = {
  draft: "#94a3b8",
  "in-progress": "#2563eb",
  "in-review": "#7c3aed",
  blocked: "#dc2626",
  shipping: "#d97706",
  archived: "#64748b",
  project: "#0f766e",
};

function quoteDot(value) {
  return `"${String(value).replaceAll("\\", "\\\\").replaceAll("\"", "\\\"")}"`;
}

export function renderDot(graph) {
  const lines = [
    "digraph worklog {",
    "  graph [rankdir=LR, overlap=false, splines=true];",
    "  node [shape=box, style=\"rounded,filled\", fontname=\"Helvetica\"];",
    "  edge [fontname=\"Helvetica\", color=\"#64748b\"];",
  ];

  for (const node of graph.nodes) {
    const color = STATUS_COLORS[node.status] || STATUS_COLORS[node.state] || "#64748b";
    const label = `${node.slug}\\n${node.status || node.state} / ${node.kind}`;
    lines.push(`  ${quoteDot(node.id)} [label=${quoteDot(label)}, fillcolor=${quoteDot(color)}, fontcolor="#ffffff", tooltip=${quoteDot(node.file || node.slug)}];`);
  }

  for (const edge of graph.edges) {
    lines.push(`  ${quoteDot(edge.source)} -> ${quoteDot(edge.target)} [label=${quoteDot(edge.relation)}, tooltip=${quoteDot(edge.note || edge.relation)}];`);
  }
  lines.push("}");
  return `${lines.join("\n")}\n`;
}

export function renderHtml(graph) {
  const dot = renderDot(graph);
  const graphJson = scriptJson(graph);
  const dotJson = scriptJson(dot);
  const instanceName = graph.instance?.name || "worklog";
  const worklogRepo = graph.instance?.roots?.worklogRepo || "";
  const nodeCount = graph.summary?.nodeCount || graph.nodes.length;
  const edgeCount = graph.summary?.edgeCount || graph.edges.length;
  const diagnosticCount = graph.summary?.diagnosticCount || 0;
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Worklog Graph - ${escapeHtml(instanceName)}</title>
<style>
html,body{width:100%;height:100%;overflow:hidden}body{margin:0;background:#f5f7fa;color:#172033;font-family:ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
body{display:grid;grid-template-rows:auto auto minmax(0,1fr);height:100dvh}
header{display:flex;justify-content:space-between;gap:16px;align-items:center;background:#fff;border-bottom:1px solid #d7dce4;padding:12px 16px;min-width:0}
h1{font-size:18px;margin:0}.meta{font-size:12px;color:#5d6778;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.controls{display:flex;gap:8px;flex-wrap:wrap;align-items:center;background:#fff;border-bottom:1px solid #d7dce4;padding:8px 12px;min-width:0}.controls label,.chip{font-size:12px;white-space:nowrap}.controls input[type=search]{width:min(320px,100%);padding:7px 9px;border:1px solid #bec7d4;border-radius:6px}.controls button{border:1px solid #bec7d4;background:#fff;border-radius:6px;padding:7px 9px;color:#172033;cursor:pointer}.controls button:hover{border-color:#64748b}.count{color:#64748b}
main{display:grid;grid-template-columns:minmax(0,1fr)minmax(320px,380px);min-height:0}body.details-collapsed main{grid-template-columns:minmax(0,1fr)0}body.details-collapsed aside{display:none}
#stage{position:relative;overflow:hidden;background:#eef1f5;min-width:0;min-height:0;touch-action:none;cursor:grab}#stage.panning{cursor:grabbing}#canvas{position:absolute;left:0;top:0;transform-origin:0 0;will-change:transform}#edges{position:absolute;inset:0;pointer-events:none;overflow:visible}
.node{position:absolute;width:230px;min-height:78px;box-sizing:border-box;border:1px solid #c6ceda;border-left:6px solid #64748b;border-radius:8px;background:#fff;box-shadow:0 2px 8px rgba(24,34,52,.08);padding:10px 11px;cursor:pointer}.node.parentNode{background:#f8fbff;border-color:#9fb0c6;box-shadow:0 4px 14px rgba(24,34,52,.13)}.node.childNode{background:#fff}.node:hover,.node.selected{border-color:#334155;box-shadow:0 5px 16px rgba(24,34,52,.16)}.node.selected{outline:2px solid #172033;outline-offset:2px}.slug{font-weight:700;font-size:13px;overflow-wrap:anywhere}.tags{margin-top:7px;display:flex;gap:5px;flex-wrap:wrap}.tag{font-size:11px;color:#334155;background:#eef2f7;border-radius:999px;padding:2px 6px}.empty{position:absolute;inset:0;display:grid;place-items:center;color:#5d6778;text-align:center;padding:24px}
aside{border-left:1px solid #d7dce4;background:#fff;overflow:auto;min-width:0}#details{padding:14px;border-bottom:1px solid #d7dce4;font-size:13px}#details h2{font-size:16px;margin:0 0 8px;overflow-wrap:anywhere}.field{margin-top:4px}.edgeGroup{margin-top:10px}.edgeGroup strong{display:block;margin-bottom:3px}.edgeGroup div{color:#334155;line-height:1.35}.reveal{margin:4px 6px 0 0;border:1px solid #bec7d4;background:#f8fafc;border-radius:6px;padding:4px 7px;color:#172033;cursor:pointer}.diag{padding:10px 14px;border-bottom:1px solid #d7dce4;background:#fff7ed;color:#7c2d12;font-size:12px}.diag strong{display:block;margin-bottom:4px}#debug{border-top:1px solid #d7dce4}#debug summary{padding:10px 14px;cursor:pointer;color:#334155;font-size:12px}pre{margin:0;padding:14px;overflow:auto;font-size:11px;line-height:1.45;background:#fbfcfe;max-height:34vh}
@media(max-width:900px){body{grid-template-rows:auto auto minmax(0,1fr)}header{display:block;padding:10px 12px}.controls{gap:6px;max-height:34dvh;overflow-y:auto;overflow-x:hidden}.controls label,.chip{white-space:normal}.controls button{padding:6px 8px}.controls input[type=search]{width:100%;min-width:0}main{grid-template-columns:1fr;grid-template-rows:minmax(0,1fr)minmax(180px,40dvh)}body.details-collapsed main{grid-template-rows:minmax(0,1fr)0}aside{border-left:0;border-top:1px solid #d7dce4}.node{width:216px}.meta{white-space:normal}}
</style>
</head>
<body>
<header><div><h1>Worklog Graph</h1><div class="meta" id="summary"></div></div><div class="meta" id="repo"></div></header>
<section class="controls">
<input id="search" type="search" list="slugs" placeholder="Search slug">
<datalist id="slugs"></datalist>
<button id="fit" type="button">Fit</button><button id="zoomOut" type="button">-</button><button id="zoomIn" type="button">+</button><button id="reset" type="button">Reset</button><button id="toggleDetails" type="button">Details</button>
<label><input type="checkbox" data-state="active" checked> active <span class="count" id="count-state-active"></span></label>
<label><input type="checkbox" data-state="archive"> archive <span class="count" id="count-state-archive"></span></label>
<label><input type="checkbox" data-state="project" checked> projects <span class="count" id="count-state-project"></span></label>
<label><input type="checkbox" data-relation="parent" checked> parent <span class="count" id="count-rel-parent"></span></label>
<label><input type="checkbox" data-relation="related"> related <span class="count" id="count-rel-related"></span></label>
<label><input type="checkbox" data-relation="project" checked> project <span class="count" id="count-rel-project"></span></label>
<label><input type="checkbox" data-relation="reopens" checked> reopens <span class="count" id="count-rel-reopens"></span></label>
<label><input type="checkbox" data-relation="supersedes" checked> supersedes <span class="count" id="count-rel-supersedes"></span></label>
<label><input type="checkbox" data-relation="superseded_by" checked> superseded <span class="count" id="count-rel-superseded_by"></span></label>
<span class="chip" id="visibleStats"></span>
</section>
<main><section id="stage"><div id="canvas"><svg id="edges"></svg></div></section><aside><div id="details"><h2>No node selected</h2><div class="field">Search or select a task to inspect its focused neighborhood.</div></div><div id="diagnostics"></div><details id="debug"><summary>DOT export</summary><pre id="dot"></pre></details></aside></main>
<script>
const graph=${graphJson};
const dot=${dotJson};
const statusColors=${scriptJson(STATUS_COLORS)};
const stage=document.getElementById("stage"),canvas=document.getElementById("canvas"),edgeSvg=document.getElementById("edges"),search=document.getElementById("search");
const CARD_W=230,CARD_H=78,COL_GAP=34,ROW_GAP=26,PAD=32;
let view={x:0,y:0,scale:1},selectedId="",canvasSize={w:800,h:600},lastVisible={nodes:[],edges:[]},userMoved=false;
document.getElementById("dot").textContent=dot;
document.getElementById("summary").textContent=${JSON.stringify(instanceName)}+" - "+${nodeCount}+" nodes, "+${edgeCount}+" edges, "+${diagnosticCount}+" diagnostics";
document.getElementById("repo").textContent=${JSON.stringify(worklogRepo)};
document.getElementById("slugs").innerHTML=graph.nodes.filter(n=>n.type==="task").map(n=>'<option value="'+esc(n.slug)+'"></option>').join("");
document.getElementById("diagnostics").innerHTML=(graph.diagnostics||[]).slice(0,8).map(d=>'<div class="diag"><strong>'+esc(d.level+' '+d.code)+'</strong>'+esc(d.message)+'<br>'+esc(d.file||'')+'</div>').join("");
function checked(selector,attr){return new Set([...document.querySelectorAll(selector)].filter(i=>i.checked).map(i=>i.getAttribute(attr)))}
function esc(s){return String(s||"").replace(/[&<>"']/g,ch=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[ch]))}
function hay(n){return [n.slug,n.status,n.kind,n.project,n.file,...(n.repos||[])].join(" ").toLowerCase()}
function countBy(items,keyFn){const out={};for(const item of items){const k=keyFn(item)||"";out[k]=(out[k]||0)+1}return out}
function setupCounts(){const states=countBy(graph.nodes,n=>n.state),rels=countBy(graph.edges,e=>e.relation);for(const k of Object.keys(states)){const el=document.getElementById("count-state-"+k);if(el)el.textContent="("+states[k]+")"}for(const k of Object.keys(rels)){const el=document.getElementById("count-rel-"+k);if(el)el.textContent="("+rels[k]+")"}}
function selectedRelations(){return checked("input[data-relation]","data-relation")}
function selectedStates(){return checked("input[data-state]","data-state")}
function exactSearch(){const q=search.value.trim().toLowerCase();if(!q)return null;return graph.nodes.find(n=>n.slug.toLowerCase()===q||n.id.toLowerCase()===q)||null}
function neighborhood(rootId,depth,relations){const ids=new Set([rootId]);let frontier=new Set([rootId]);for(let i=0;i<depth;i++){const next=new Set();for(const e of graph.edges){if(!relations.has(e.relation))continue;if(frontier.has(e.source)&&!ids.has(e.target)){ids.add(e.target);next.add(e.target)}if(frontier.has(e.target)&&!ids.has(e.source)){ids.add(e.source);next.add(e.source)}}frontier=next}return ids}
function visible(){const states=selectedStates(),relations=selectedRelations(),q=search.value.trim().toLowerCase(),exact=exactSearch();if(exact)selectedId=exact.id;let ids=null;if(selectedId){ids=neighborhood(selectedId,2,relations)}let nodes=graph.nodes.filter(n=>(states.has(n.state)||n.id===selectedId)&&(!ids||ids.has(n.id)));if(q&&!exact&&!selectedId)nodes=nodes.filter(n=>hay(n).includes(q));const nodeIds=new Set(nodes.map(n=>n.id));const edges=graph.edges.filter(e=>nodeIds.has(e.source)&&nodeIds.has(e.target)&&relations.has(e.relation));return{nodes,edges}}
function nodeOrder(a,b){const ak=(a.project||"zz")+" "+(a.kind==="project"?"0":"1")+" "+(a.status||"")+" "+a.slug;const bk=(b.project||"zz")+" "+(b.kind==="project"?"0":"1")+" "+(b.status||"")+" "+b.slug;return ak.localeCompare(bk)}
function placeRows(rows,cols,stageW){const pos=new Map();let y=PAD;for(const row of rows){const sorted=[...row].sort(nodeOrder),lines=Math.max(1,Math.ceil(sorted.length/cols));for(let line=0;line<lines;line++){const slice=sorted.slice(line*cols,(line+1)*cols),used=slice.length*CARD_W+Math.max(0,slice.length-1)*COL_GAP,start=Math.max(PAD,(stageW-used)/2);slice.forEach((n,i)=>pos.set(n.id,{x:start+i*(CARD_W+COL_GAP),y:y+line*(CARD_H+ROW_GAP)}))}y+=lines*(CARD_H+ROW_GAP)+ROW_GAP}return pos}
function layout(nodes,edges){const stageW=Math.max(320,stage.clientWidth||900),cols=Math.max(1,Math.floor((stageW-PAD*2+COL_GAP)/(CARD_W+COL_GAP))),ids=new Set(nodes.map(n=>n.id)),parentEdges=edges.filter(e=>e.relation==="parent"&&ids.has(e.source)&&ids.has(e.target));if(!parentEdges.length){const sorted=[...nodes].sort(nodeOrder);if(selectedId)sorted.sort((a,b)=>(a.id===selectedId?-1:0)+(b.id===selectedId?1:0));return placeRows([sorted],cols,stageW)}const byId=new Map(nodes.map(n=>[n.id,n])),children=new Map(),incoming=new Map(nodes.map(n=>[n.id,0]));for(const e of parentEdges){(children.get(e.source)||children.set(e.source,[]).get(e.source)).push(e.target);incoming.set(e.target,(incoming.get(e.target)||0)+1)}const rank=new Map(),queue=[];for(const n of nodes){if((incoming.get(n.id)||0)===0&&(children.get(n.id)||[]).length){rank.set(n.id,0);queue.push(n.id)}}for(let i=0;i<queue.length;i++){const id=queue[i],nextRank=(rank.get(id)||0)+1;for(const child of children.get(id)||[]){if(!rank.has(child)||rank.get(child)<nextRank){rank.set(child,nextRank);queue.push(child)}}}let maxRank=Math.max(0,...rank.values());for(const n of nodes){if(!rank.has(n.id))rank.set(n.id,(children.get(n.id)||[]).length?0:maxRank+1)}const rows=[];for(const n of nodes){const r=rank.get(n.id);(rows[r]||=[]).push(n)}return placeRows(rows.filter(Boolean),cols,stageW)}
function relationColor(rel){return({parent:"#2563eb",project:"#0f766e",related:"#64748b",reopens:"#d97706",supersedes:"#7c3aed",superseded_by:"#7c3aed"}[rel]||"#64748b")}
function applyView(){canvas.style.transform="translate("+view.x+"px,"+view.y+"px) scale("+view.scale+")"}
function fitView(){const rect=stage.getBoundingClientRect(),mobile=rect.width<700;const fitWidth=(rect.width-32)/canvasSize.w,fitAll=Math.min((rect.width-48)/canvasSize.w,(rect.height-48)/canvasSize.h);const scale=Math.max(mobile ? .72 : .25,Math.min(1.25,mobile?fitWidth:fitAll));view={scale,x:(rect.width-canvasSize.w*scale)/2,y:mobile?16:(rect.height-canvasSize.h*scale)/2};applyView();userMoved=false}
function resetView(){view={x:24,y:24,scale:1};applyView();userMoved=true}
function zoomAt(factor,cx,cy){const next=Math.max(.2,Math.min(3,view.scale*factor));const wx=(cx-view.x)/view.scale,wy=(cy-view.y)/view.scale;view.x=cx-wx*next;view.y=cy-wy*next;view.scale=next;applyView();userMoved=true}
function render(){const vg=visible(),pos=layout(vg.nodes,vg.edges);lastVisible=vg;canvas.querySelectorAll(".node,.empty").forEach(n=>n.remove());edgeSvg.innerHTML="";let maxX=stage.clientWidth,maxY=stage.clientHeight;for(const p of pos.values()){maxX=Math.max(maxX,p.x+CARD_W+PAD);maxY=Math.max(maxY,p.y+CARD_H+PAD)}canvasSize={w:maxX,h:maxY};canvas.style.width=maxX+"px";canvas.style.height=maxY+"px";edgeSvg.setAttribute("width",maxX);edgeSvg.setAttribute("height",maxY);if(!vg.nodes.length){const empty=document.createElement("div");empty.className="empty";empty.textContent="No visible tasks. Relax filters or search another slug.";canvas.appendChild(empty)}const parentIds=new Set(vg.edges.filter(e=>e.relation==="parent").map(e=>e.source)),childIds=new Set(vg.edges.filter(e=>e.relation==="parent").map(e=>e.target));for(const n of vg.nodes){const p=pos.get(n.id),color=statusColors[n.status]||statusColors[n.state]||"#64748b";const el=document.createElement("div");el.className="node"+(parentIds.has(n.id)?" parentNode":"")+(childIds.has(n.id)?" childNode":"")+(n.id===selectedId?" selected":"");el.dataset.id=n.id;el.style.left=p.x+"px";el.style.top=p.y+"px";el.style.borderLeftColor=color;el.innerHTML='<div class="slug">'+esc(n.slug)+'</div><div class="tags"><span class="tag">'+esc(n.status||n.state)+'</span><span class="tag">'+esc(n.kind||"-")+'</span><span class="tag">'+esc(n.ldap||"project")+'</span></div>';el.addEventListener("click",ev=>{ev.stopPropagation();selectedId=n.id;search.value=n.slug;render();selectNode(n,lastVisible)});canvas.appendChild(el)}for(const e of vg.edges){const a=pos.get(e.source),b=pos.get(e.target);if(!a||!b)continue;let x1=a.x+CARD_W/2,y1=a.y+CARD_H/2,x2=b.x+CARD_W/2,y2=b.y+CARD_H/2;if(e.relation==="parent"){y1=a.y+CARD_H;y2=b.y}const path=document.createElementNS("http://www.w3.org/2000/svg","path");path.setAttribute("d","M "+x1+" "+y1+" C "+x1+" "+((y1+y2)/2)+", "+x2+" "+((y1+y2)/2)+", "+x2+" "+y2);path.setAttribute("stroke",relationColor(e.relation));path.setAttribute("stroke-width",e.relation==="parent"?"2":(selectedId&&(e.source===selectedId||e.target===selectedId)?"2.2":"1.2"));path.setAttribute("fill","none");path.setAttribute("opacity",e.relation==="parent"?".72":(selectedId&&(e.source!==selectedId&&e.target!==selectedId)?".22":".5"));edgeSvg.appendChild(path)}document.getElementById("visibleStats").textContent=vg.nodes.length+" visible nodes, "+vg.edges.length+" visible edges";if(!userMoved)fitView();if(selectedId){const node=graph.nodes.find(n=>n.id===selectedId);if(node)selectNode(node,vg)}else resetDetails()}
function groupName(e,n){if(e.relation==="parent")return e.target===n.id?"Parents":"Children";if(e.relation==="project")return "Same project";if(e.relation==="related")return "Related";if(e.relation==="reopens")return "Reopens";if(e.relation==="supersedes"||e.relation==="superseded_by")return "Supersedes";return e.relation}
function edgeLine(e){return esc(e.source)+" -> "+esc(e.target)+(e.note?": "+esc(e.note):"")}
function resetDetails(){document.getElementById("details").innerHTML='<h2>No node selected</h2><div class="field">Search or select a task to inspect its focused neighborhood.</div>'}
function selectNode(n,vg){const visibleIds=new Set(vg.edges.map(e=>e.id));const incident=graph.edges.filter(e=>e.source===n.id||e.target===n.id);const hidden=incident.filter(e=>!visibleIds.has(e.id));const groups={};for(const e of incident.filter(e=>visibleIds.has(e.id))){const k=groupName(e,n);(groups[k]||=[]).push(e)}let html='<h2>'+esc(n.slug)+'</h2><div class="field"><b>Status:</b> '+esc(n.status||n.state)+' / '+esc(n.kind)+'</div><div class="field"><b>Next:</b> '+esc(n.frontmatter?.next_action||"-")+'</div><div class="field"><b>File:</b> '+esc(n.file||"-")+'</div><div class="field"><b>Project:</b> '+esc(n.project||"-")+'</div><div class="field"><b>Repos:</b> '+esc((n.repos||[]).join(", ")||"-")+'</div>';html+='<div class="edgeGroup"><strong>Visible relation groups</strong>';for(const [k,items] of Object.entries(groups)){html+='<div><b>'+esc(k)+'</b> ('+items.length+')<br>'+items.slice(0,8).map(edgeLine).join("<br>")+(items.length>8?"<br>...":"")+'</div>'}if(!Object.keys(groups).length)html+='<div>-</div>';html+='</div>';if(hidden.length){const rels=[...new Set(hidden.map(e=>e.relation))],states=[...new Set(hidden.flatMap(e=>[graph.nodes.find(n=>n.id===e.source)?.state,graph.nodes.find(n=>n.id===e.target)?.state]).filter(Boolean).filter(s=>!selectedStates().has(s)))];html+='<div class="edgeGroup"><strong>Hidden incident edges: '+hidden.length+'</strong>';for(const rel of rels){if(!selectedRelations().has(rel))html+='<button class="reveal" data-reveal-relation="'+esc(rel)+'">Show '+esc(rel)+'</button>'}for(const st of states){html+='<button class="reveal" data-reveal-state="'+esc(st)+'">Show '+esc(st)+'</button>'}html+='</div>'}document.getElementById("details").innerHTML=html}
let pointers=new Map(),panStart=null,pinchStart=null;
stage.addEventListener("pointerdown",ev=>{if(ev.target.closest(".node,button,input,label"))return;stage.setPointerCapture(ev.pointerId);pointers.set(ev.pointerId,{x:ev.clientX,y:ev.clientY});if(pointers.size===1){panStart={x:ev.clientX,y:ev.clientY,vx:view.x,vy:view.y};stage.classList.add("panning")}if(pointers.size===2){const pts=[...pointers.values()];pinchStart={dist:Math.hypot(pts[0].x-pts[1].x,pts[0].y-pts[1].y),scale:view.scale,x:(pts[0].x+pts[1].x)/2,y:(pts[0].y+pts[1].y)/2}}});
stage.addEventListener("pointermove",ev=>{if(!pointers.has(ev.pointerId))return;pointers.set(ev.pointerId,{x:ev.clientX,y:ev.clientY});if(pointers.size===2&&pinchStart){const pts=[...pointers.values()],dist=Math.hypot(pts[0].x-pts[1].x,pts[0].y-pts[1].y);zoomAt(dist/pinchStart.dist,pinchStart.x,pinchStart.y);pinchStart.dist=dist;return}if(panStart){view.x=panStart.vx+ev.clientX-panStart.x;view.y=panStart.vy+ev.clientY-panStart.y;applyView();userMoved=true}});
function endPointer(ev){pointers.delete(ev.pointerId);panStart=null;pinchStart=null;stage.classList.remove("panning")}
stage.addEventListener("pointerup",endPointer);stage.addEventListener("pointercancel",endPointer);
stage.addEventListener("wheel",ev=>{ev.preventDefault();const rect=stage.getBoundingClientRect();zoomAt(ev.deltaY<0?1.12:.88,ev.clientX-rect.left,ev.clientY-rect.top)},{passive:false});
document.getElementById("fit").addEventListener("click",fitView);document.getElementById("reset").addEventListener("click",resetView);document.getElementById("zoomIn").addEventListener("click",()=>zoomAt(1.18,stage.clientWidth/2,stage.clientHeight/2));document.getElementById("zoomOut").addEventListener("click",()=>zoomAt(.85,stage.clientWidth/2,stage.clientHeight/2));document.getElementById("toggleDetails").addEventListener("click",()=>document.body.classList.toggle("details-collapsed"));
document.getElementById("details").addEventListener("click",ev=>{const rel=ev.target.getAttribute("data-reveal-relation"),st=ev.target.getAttribute("data-reveal-state");if(rel){const input=document.querySelector('input[data-relation="'+rel+'"]');if(input)input.checked=true}if(st){const input=document.querySelector('input[data-state="'+st+'"]');if(input)input.checked=true}if(rel||st){userMoved=false;render()}});
search.addEventListener("input",()=>{const exact=exactSearch();selectedId=exact?exact.id:"";userMoved=false;render()});
document.querySelectorAll("input:not(#search)").forEach(input=>input.addEventListener("input",()=>{userMoved=false;render()}));window.addEventListener("resize",()=>{userMoved=false;render()});setupCounts();render();
</script>
</body>
</html>
`;
}

function scriptJson(value) {
  return JSON.stringify(value)
    .replaceAll("<", "\\u003c")
    .replaceAll(">", "\\u003e")
    .replaceAll("&", "\\u0026");
}

function escapeHtml(value) {
  return String(value || "").replace(/[&<>"']/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[ch]));
}

export function writeOutput(text, output) {
  if (!output) {
    process.stdout.write(text);
    return;
  }
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, text);
  console.log(output);
}
