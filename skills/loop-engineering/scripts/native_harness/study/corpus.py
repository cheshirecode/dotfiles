"""Frozen repair fixtures and controller-side cases; never copy answers to workers."""

from dataclasses import dataclass


@dataclass(frozen=True)
class Task:
    name: str
    language: str
    contract: str
    broken: str
    reference: str
    cases: tuple
    driver: str = ""
    setup: str = ""

    @property
    def filename(self):
        return {
            "python": "src/repair.py",
            "javascript": "src/repair.cjs",
            "shell": "src/repair.sh",
            "sql": "src/repair.sql",
        }[self.language]


TASKS = []


def add(name, language, contract, broken, reference, cases, driver="", setup=""):
    TASKS.append(
        Task(
            name,
            language,
            contract,
            broken.strip() + "\n",
            reference.strip() + "\n",
            tuple(cases),
            driver,
            setup,
        )
    )


add(
    "interval-union",
    "python",
    "run(intervals) returns sorted inclusive integer intervals with overlaps and adjacency merged. "
    "Input is unsorted; endpoints are ordered. Do not mutate the input.",
    "def run(xs):\n    return xs",
    """
def run(xs):
    result=[]
    for a,b in sorted(xs):
        if result and a<=result[-1][1]+1:
            result[-1][1]=max(result[-1][1],b)
        else: result.append([a,b])
    return result
""",
    [
        ([[3, 5], [1, 2]], [[1, 5]]),
        ([[1, 4], [2, 3]], [[1, 4]]),
        ([], []),
        ([[8, 9], [-3, -1], [0, 0], [2, 4], [4, 7]], [[-3, 0], [2, 9]]),
        ([[2, 2], [2, 2]], [[2, 2]]),
        ([[1, 1], [3, 3]], [[1, 1], [3, 3]]),
    ],
)

add(
    "quoted-csv",
    "python",
    "run(text) parses a comma-separated table using the first nonblank record as headers. "
    "Honor quoted commas, doubled quotes and embedded newlines, skip blank records, preserve "
    "spaces in fields. Return a list of row dictionaries; unequal column counts raise ValueError.",
    "def run(text):\n    rows=text.splitlines()\n    return [dict(zip(rows[0].split(','), r.split(','))) for r in rows[1:]]",
    """
import csv,io
def run(text):
    rows=[r for r in csv.reader(io.StringIO(text)) if r]
    if not rows:return []
    head=rows[0];out=[]
    for row in rows[1:]:
        if len(row)!=len(head):raise ValueError('columns')
        out.append(dict(zip(head,row)))
    return out
""",
    [
        ('name,note\na,"hello, world"\n', [{"name": "a", "note": "hello, world"}]),
        ("a,b\n1,2\n", [{"a": "1", "b": "2"}]),
        ("", []),
        ('\na,b\n\n"x\ny","he said ""yes"""\n', [{"a": "x\ny", "b": 'he said "yes"'}]),
        ("a,b\n1\n", {"error": "ValueError"}),
        ("a,b\r\n 1 ,\r\n", [{"a": " 1 ", "b": ""}]),
    ],
)

add(
    "path-containment",
    "python",
    "run({root,path}) joins an absolute POSIX root with a relative user path without filesystem "
    "access. Percent-decode the path once and treat backslashes as separators; normalize dot "
    "segments in both root and path and remove trailing slashes except for /. Reject absolute "
    "paths and escapes above root with ValueError. Empty path returns the normalized root.",
    "def run(d):\n    return d['root'].rstrip('/')+'/'+d['path']",
    """
import posixpath
from urllib.parse import unquote
def run(d):
    root=posixpath.normpath(d['root']);p=unquote(d['path']).replace('\\\\','/')
    if p.startswith('/'):raise ValueError('absolute')
    value=posixpath.normpath(posixpath.join(root,p))
    if posixpath.commonpath([root,value])!=root:raise ValueError('escape')
    return value
""",
    [
        ({"root": "/srv/data", "path": "a/../b"}, "/srv/data/b"),
        ({"root": "/srv/data", "path": "../secret"}, {"error": "ValueError"}),
        ({"root": "/srv/data/", "path": ""}, "/srv/data"),
        ({"root": "/srv/data", "path": "%2e%2e%2fdata2/x"}, {"error": "ValueError"}),
        ({"root": "/srv/data", "path": "a\\..\\b"}, "/srv/data/b"),
        ({"root": "/srv/data", "path": "%2fetc/x"}, {"error": "ValueError"}),
    ],
)

add(
    "dependency-order",
    "python",
    "run(graph) accepts a mapping from task name to dependency names. Include dependency-only "
    "vertices, emit each vertex once, and always choose the lexicographically smallest currently "
    "ready vertex. Duplicate edges are harmless. Cycles raise ValueError. Input must remain unchanged.",
    "def run(graph):\n    return sorted(graph)",
    """
def run(graph):
    nodes=set(graph)|{d for ds in graph.values() for d in ds}
    pending={k:set(graph.get(k,[])) for k in nodes};out=[]
    while pending:
        ready=sorted(k for k,v in pending.items() if not v)
        if not ready:raise ValueError('cycle')
        k=ready[0];out.append(k);del pending[k]
        for deps in pending.values():deps.discard(k)
    return out
""",
    [
        ({"app": ["lib"], "lib": []}, ["lib", "app"]),
        ({"a": ["z"]}, ["z", "a"]),
        ({}, []),
        ({"b": ["a", "a"], "c": [], "a": []}, ["a", "b", "c"]),
        ({"a": ["b"], "b": ["a"]}, {"error": "ValueError"}),
        ({"a": ["a"]}, {"error": "ValueError"}),
    ],
)

add(
    "cursor-pagination",
    "python",
    "run({start,pages}) collects page items in traversal order. pages is keyed by string cursors, "
    "each value has items and next. Only null terminates: empty string and zero are valid cursors. "
    "Preserve duplicates; a repeated cursor raises ValueError and a missing page raises KeyError.",
    "def run(d):\n    out=[];c=d['start']\n    while c:\n        p=d['pages'][str(c)];out+=p['items'];c=p['next']\n    return out",
    """
def run(d):
    out=[];seen=set();c=d['start']
    while c is not None:
        k=str(c)
        if k in seen:raise ValueError('cycle')
        seen.add(k);p=d['pages'][k];out.extend(p['items']);c=p['next']
    return out
""",
    [
        ({"start": 0, "pages": {"0": {"items": [1], "next": None}}}, [1]),
        (
            {
                "start": "a",
                "pages": {
                    "a": {"items": [1], "next": ""},
                    "": {"items": [2], "next": None},
                },
            },
            [1, 2],
        ),
        ({"start": None, "pages": {}}, []),
        (
            {
                "start": "a",
                "pages": {
                    "a": {"items": [1, 1], "next": "b"},
                    "b": {"items": [], "next": None},
                },
            },
            [1, 1],
        ),
        (
            {"start": "a", "pages": {"a": {"items": [], "next": "a"}}},
            {"error": "ValueError"},
        ),
        ({"start": "missing", "pages": {}}, {"error": "KeyError"}),
    ],
)

add(
    "invoice-rounding",
    "python",
    "run({items,discount_bps}) returns a two-decimal currency string. Each item has decimal-string "
    "price and integer qty. Sum exact extended prices, apply integer basis-point discount, then "
    "round once using decimal ROUND_HALF_UP. Empty invoices are 0.00. Negative quantity raises ValueError.",
    "def run(d):\n    return format(sum(float(x['price'])*x['qty'] for x in d['items'])*(1-d['discount_bps']/10000),'.2f')",
    """
from decimal import Decimal,ROUND_HALF_UP
def run(d):
    total=Decimal(0)
    for x in d['items']:
        if x['qty']<0:raise ValueError('quantity')
        total+=Decimal(x['price'])*x['qty']
    total*=Decimal(10000-d['discount_bps'])/Decimal(10000)
    return format(total.quantize(Decimal('.01'),rounding=ROUND_HALF_UP),'.2f')
""",
    [
        ({"items": [{"price": "1.005", "qty": 1}], "discount_bps": 0}, "1.01"),
        ({"items": [{"price": "10", "qty": 2}], "discount_bps": 2500}, "15.00"),
        ({"items": [], "discount_bps": 0}, "0.00"),
        (
            {
                "items": [{"price": ".005", "qty": 1}, {"price": ".005", "qty": 1}],
                "discount_bps": 0,
            },
            "0.01",
        ),
        (
            {"items": [{"price": "9.99", "qty": -1}], "discount_bps": 0},
            {"error": "ValueError"},
        ),
        ({"items": [{"price": "999999.995", "qty": 1}], "discount_bps": 10000}, "0.00"),
    ],
)

add(
    "config-overlay",
    "python",
    "run({base,patch}) recursively overlays dictionaries. Patch null deletes a key; lists and "
    "scalars replace rather than merge. Dictionary patches over a scalar start from an empty "
    "dictionary. Missing deletion is harmless. Never mutate base or patch.",
    "def run(d):\n    out=d['base'].copy();out.update(d['patch']);return out",
    """
import copy
def merge(base,patch):
    out=copy.deepcopy(base) if isinstance(base,dict) else {}
    for k,v in patch.items():
        if v is None:out.pop(k,None)
        elif isinstance(v,dict):out[k]=merge(out.get(k),v)
        else:out[k]=copy.deepcopy(v)
    return out
def run(d):return merge(d['base'],d['patch'])
""",
    [
        (
            {"base": {"a": {"x": 1, "y": 2}}, "patch": {"a": {"y": 3}}},
            {"a": {"x": 1, "y": 3}},
        ),
        ({"base": {"x": 1}, "patch": {"x": None}}, {}),
        ({"base": {"x": [1, 2]}, "patch": {"x": [3]}}, {"x": [3]}),
        ({"base": {"x": 3}, "patch": {"x": {"a": 1}}}, {"x": {"a": 1}}),
        ({"base": {}, "patch": {"missing": None}}, {}),
        (
            {"base": {"a": {"x": 1}}, "patch": {"a": {"x": None, "z": False}}},
            {"a": {"z": False}},
        ),
    ],
)

add(
    "sliding-window",
    "python",
    "run({times,window,limit}) returns admission booleans for nondecreasing integer timestamps. "
    "At t count only admitted requests with timestamp strictly greater than t-window. Rejected "
    "requests do not consume quota. window and limit must be positive, otherwise ValueError.",
    "def run(d):\n    return [i<d['limit'] for i,t in enumerate(d['times'])]",
    """
def run(d):
    if d['window']<=0 or d['limit']<=0:raise ValueError('bounds')
    active=[];out=[]
    for t in d['times']:
        active=[x for x in active if x>t-d['window']]
        ok=len(active)<d['limit'];out.append(ok)
        if ok:active.append(t)
    return out
""",
    [
        ({"times": [0, 1, 10], "window": 10, "limit": 2}, [True, True, True]),
        ({"times": [0, 0, 0, 1], "window": 5, "limit": 2}, [True, True, False, False]),
        ({"times": [], "window": 5, "limit": 1}, []),
        (
            {"times": [0, 1, 2, 3, 5], "window": 3, "limit": 1},
            [True, False, False, True, False],
        ),
        ({"times": [0], "window": 0, "limit": 1}, {"error": "ValueError"}),
        ({"times": [0], "window": 1, "limit": 0}, {"error": "ValueError"}),
    ],
)

add(
    "stable-identity",
    "javascript",
    "Export run(items): preserve the first object for each id in input order. Numeric and string "
    "ids differ, and __proto__ is an ordinary string key. Do not mutate the input.",
    "module.exports = xs => Object.values(Object.fromEntries(xs.map(x=>[x.id,x])));",
    "module.exports=xs=>{const seen=new Set();return xs.filter(x=>{if(seen.has(x.id))return false;seen.add(x.id);return true;});};",
    [
        ([{"id": "a", "v": 1}, {"id": "a", "v": 2}], [{"id": "a", "v": 1}]),
        ([{"id": 1}, {"id": "1"}], [{"id": 1}, {"id": "1"}]),
        ([], []),
        (
            [{"id": "10"}, {"id": "2"}, {"id": "1"}],
            [{"id": "10"}, {"id": "2"}, {"id": "1"}],
        ),
        ([{"id": "__proto__"}, {"id": "__proto__"}], [{"id": "__proto__"}]),
        ([{"id": None}, {"id": False}, {"id": None}], [{"id": None}, {"id": False}]),
    ],
)

MAP_DRIVER = """
const mapLimit=require('./src/repair.cjs');
let active=0,peak=0;
const result=await mapLimit(data.items,data.limit,async x=>{
  active++;peak=Math.max(peak,active);await new Promise(r=>setTimeout(r,x.delay));active--;return x.value*2;
});
return {result,peak};
"""
add(
    "bounded-async-map",
    "javascript",
    "Export async mapLimit(items, limit, fn). Start no more than limit callbacks concurrently, "
    "preserve input order in returned results, fill available slots, handle empty input, and reject "
    "nonpositive/noninteger limits with RangeError. Do not mutate inputs.",
    "module.exports=async(xs,limit,fn)=>Promise.all(xs.map(fn));",
    """
module.exports=async function(xs,limit,fn){
 if(!Number.isInteger(limit)||limit<1)throw new RangeError('limit');
 let next=0;const out=new Array(xs.length);
 async function worker(){while(next<xs.length){const i=next++;out[i]=await fn(xs[i],i);}}
 await Promise.all(Array.from({length:Math.min(limit,xs.length)},worker));return out;
};
""",
    [
        (
            {
                "items": [
                    {"value": 1, "delay": 8},
                    {"value": 2, "delay": 1},
                    {"value": 3, "delay": 2},
                ],
                "limit": 2,
            },
            {"result": [2, 4, 6], "peak": 2},
        ),
        (
            {"items": [{"value": 2, "delay": 1}, {"value": 4, "delay": 1}], "limit": 1},
            {"result": [4, 8], "peak": 1},
        ),
        ({"items": [], "limit": 3}, {"result": [], "peak": 0}),
        (
            {"items": [{"value": -1, "delay": 1}], "limit": 5},
            {"result": [-2], "peak": 1},
        ),
        ({"items": [], "limit": 0}, {"error": "RangeError"}),
        ({"items": [], "limit": 1.5}, {"error": "RangeError"}),
    ],
    MAP_DRIVER,
)

MEMO_DRIVER = """
const memoize=require('./src/repair.cjs');let calls=0;
const f=memoize(async key=>{calls++;await new Promise(r=>setTimeout(r,1));if(calls<=data.failures)throw Error('retry');return key+':'+calls;});
const first=await Promise.all(data.keys.map(k=>f(k).catch(e=>'error')));
const second=await Promise.all(data.keys.map(k=>f(k).catch(e=>'error')));
return {first,second,calls};
"""
add(
    "promise-memoization",
    "javascript",
    "Export memoize(asyncFn), returning a function of one string key. Coalesce concurrent calls "
    "with the same key, cache successful results, and evict rejected promises so later calls retry. "
    "Different keys are independent; __proto__ is an ordinary key.",
    "module.exports=fn=>{const cache=new Map();return k=>{if(!cache.has(k))cache.set(k,fn(k));return cache.get(k);};};",
    "module.exports=fn=>{const cache=new Map();return k=>{if(!cache.has(k)){const p=Promise.resolve().then(()=>fn(k));cache.set(k,p);p.catch(()=>{if(cache.get(k)===p)cache.delete(k);});}return cache.get(k);};};",
    [
        (
            {"keys": ["a", "a"], "failures": 1},
            {"first": ["error", "error"], "second": ["a:2", "a:2"], "calls": 2},
        ),
        (
            {"keys": ["a", "a"], "failures": 0},
            {"first": ["a:1", "a:1"], "second": ["a:1", "a:1"], "calls": 1},
        ),
        ({"keys": [], "failures": 0}, {"first": [], "second": [], "calls": 0}),
        (
            {"keys": ["__proto__"], "failures": 1},
            {"first": ["error"], "second": ["__proto__:2"], "calls": 2},
        ),
        (
            {"keys": ["x"], "failures": 2},
            {"first": ["error"], "second": ["error"], "calls": 2},
        ),
        (
            {"keys": ["a", "b"], "failures": 0},
            {"first": ["a:2", "b:2"], "second": ["a:2", "b:2"], "calls": 2},
        ),
    ],
    MEMO_DRIVER,
)

RETRY_DRIVER = """
const retry=require('./src/repair.cjs');let calls=0;
try{const value=await retry(async()=>{calls++;if(calls<=data.failures){const e=Error('failure-'+calls);e.retryable=data.retryable;throw e;}return 'ok';},data.attempts);return {value,calls};}
catch(e){return {error:e.name,message:e.message,calls};}
"""
add(
    "retry-budget",
    "javascript",
    "Export async retry(fn, attempts). attempts includes the first call and must be a positive "
    "integer (otherwise RangeError with message 'attempts', before calling fn). Retry only errors "
    "whose retryable property is true. Preserve the last original error when exhausted.",
    "module.exports=async(fn,n)=>{for(let i=0;i<=n;i++){try{return await fn();}catch(e){if(i===n)throw e;}}};",
    "module.exports=async(fn,n)=>{if(!Number.isInteger(n)||n<1)throw new RangeError('attempts');for(let i=0;i<n;i++){try{return await fn();}catch(e){if(e.retryable!==true||i===n-1)throw e;}}};",
    [
        (
            {"failures": 3, "retryable": True, "attempts": 2},
            {"error": "Error", "message": "failure-2", "calls": 2},
        ),
        (
            {"failures": 1, "retryable": True, "attempts": 2},
            {"value": "ok", "calls": 2},
        ),
        (
            {"failures": 3, "retryable": False, "attempts": 4},
            {"error": "Error", "message": "failure-1", "calls": 1},
        ),
        (
            {"failures": 0, "retryable": True, "attempts": 1},
            {"value": "ok", "calls": 1},
        ),
        (
            {"failures": 0, "retryable": True, "attempts": 0},
            {"error": "RangeError", "message": "attempts", "calls": 0},
        ),
        (
            {"failures": 0, "retryable": True, "attempts": 1.5},
            {"error": "RangeError", "message": "attempts", "calls": 0},
        ),
    ],
    RETRY_DRIVER,
)

add(
    "query-multimap",
    "javascript",
    "Export run(query): parse an optional leading ? query into an object mapping each key to all "
    "its values in order. Decode percent escapes and + spaces; a bare key has empty value; ignore "
    "empty segments. Keys like __proto__ must work. Values may contain encoded equals signs.",
    "module.exports=q=>Object.fromEntries(q.replace(/^\\?/, '').split('&').map(x=>x.split('=')));",
    "module.exports=q=>{const out=Object.create(null);for(const[k,v]of new URLSearchParams(q)){(out[k]??=[]).push(v);}return out;};",
    [
        ("?a=1&a=2", {"a": ["1", "2"]}),
        ("q=hello+world&x=a%3Db", {"q": ["hello world"], "x": ["a=b"]}),
        ("", {}),
        ("&&flag&&", {"flag": [""]}),
        ("__proto__=x&constructor=y", {"__proto__": ["x"], "constructor": ["y"]}),
        ("%E2%9C%93=%2B&empty=", {"✓": ["+"], "empty": [""]}),
    ],
)

add(
    "deep-json-equality",
    "javascript",
    "Export run({a,b}): structural equality for JSON values. Object key order is irrelevant, "
    "array order matters, arrays differ from objects, null differs from {}, and types are strict.",
    "module.exports=({a,b})=>JSON.stringify(a)===JSON.stringify(b);",
    """
function eq(a,b){if(a===b)return true;if(a===null||b===null||typeof a!=='object'||typeof b!=='object')return false;
if(Array.isArray(a)!==Array.isArray(b))return false;const ka=Object.keys(a),kb=Object.keys(b);
return ka.length===kb.length&&ka.every(k=>Object.hasOwn(b,k)&&eq(a[k],b[k]));}
module.exports=({a,b})=>eq(a,b);
""",
    [
        ({"a": {"x": 1, "y": 2}, "b": {"y": 2, "x": 1}}, True),
        ({"a": [1, 2], "b": [2, 1]}, False),
        ({"a": None, "b": {}}, False),
        ({"a": [], "b": {}}, False),
        ({"a": {"n": [{"x": False}]}, "b": {"n": [{"x": 0}]}}, False),
        ({"a": {"__proto__": 1}, "b": {"__proto__": 1}}, True),
    ],
)

EVENT_DRIVER = """
const Emitter=require('./src/repair.cjs');const e=new Emitter();const out=[];
let off;
off=e.on('x',v=>{out.push('a'+v);if(data.remove)off();});
e.once('x',v=>{out.push('b'+v);if(data.reenter)e.emit('x',9);});
for(const v of data.values)e.emit('x',v);
return out;
"""
add(
    "reentrant-events",
    "javascript",
    "Export an Emitter class with on(event,fn) returning an idempotent unsubscribe function, "
    "once(event,fn), and emit(event,value). Emit a snapshot in registration order. Remove once "
    "listeners before calling them so reentrant emit cannot call them twice. Unsubscribe affects "
    "future emissions, not the current snapshot.",
    """
module.exports=class{constructor(){this.m=new Map();}on(k,f){const a=this.m.get(k)||[];a.push(f);this.m.set(k,a);return()=>this.m.set(k,(this.m.get(k)||[]).filter(x=>x!==f));}once(k,f){this.on(k,f);}emit(k,v){for(const f of this.m.get(k)||[])f(v);}};
""",
    """
module.exports=class{constructor(){this.m=new Map();}
on(k,f){const entry={f};const a=this.m.get(k)||[];a.push(entry);this.m.set(k,a);return()=>this.m.set(k,(this.m.get(k)||[]).filter(x=>x!==entry));}
once(k,f){const off=this.on(k,v=>{off();f(v);});return off;}
emit(k,v){for(const {f} of [...(this.m.get(k)||[])])f(v);}};
""",
    [
        ({"values": [1, 2], "remove": False, "reenter": False}, ["a1", "b1", "a2"]),
        ({"values": [1, 2], "remove": True, "reenter": False}, ["a1", "b1"]),
        ({"values": [1], "remove": False, "reenter": True}, ["a1", "b1", "a9"]),
        ({"values": [], "remove": True, "reenter": False}, []),
        (
            {"values": [1, 2, 3], "remove": False, "reenter": False},
            ["a1", "b1", "a2", "a3"],
        ),
        ({"values": [1, 2], "remove": True, "reenter": True}, ["a1", "b1"]),
    ],
    EVENT_DRIVER,
)

CACHE_DRIVER = """
const Cache=require('./src/repair.cjs');let now=0;const c=new Cache(()=>now);const out=[];
for(const op of data){now=op.time;if(op.kind==='set')c.set(op.key,op.value,op.ttl);else out.push(c.get(op.key)??null);}
return out;
"""
add(
    "ttl-cache",
    "javascript",
    "Export Cache(clock) class. set(key,value,ttl) replaces a value with expiration clock()+ttl. "
    "get returns undefined when missing or clock() >= expiration; ttl 0 expires immediately. "
    "Use the injected clock, support false/0/empty-string values and __proto__ keys.",
    "module.exports=class{constructor(clock){this.clock=clock;this.m={};}set(k,v,t){this.m[k]={v,end:this.clock()+t};}get(k){const x=this.m[k];return x&&this.clock()<=x.end?x.v:undefined;}};",
    "module.exports=class{constructor(clock){this.clock=clock;this.m=new Map();}set(k,v,t){this.m.set(k,{v,end:this.clock()+t});}get(k){const x=this.m.get(k);if(!x)return undefined;if(this.clock()>=x.end){this.m.delete(k);return undefined;}return x.v;}};",
    [
        (
            [
                {"time": 0, "kind": "set", "key": "x", "value": 1, "ttl": 2},
                {"time": 2, "kind": "get", "key": "x"},
            ],
            [None],
        ),
        ([{"time": 0, "kind": "get", "key": "x"}], [None]),
        (
            [
                {"time": 0, "kind": "set", "key": "x", "value": False, "ttl": 2},
                {"time": 1, "kind": "get", "key": "x"},
            ],
            [False],
        ),
        (
            [
                {"time": 0, "kind": "set", "key": "x", "value": 0, "ttl": 0},
                {"time": 0, "kind": "get", "key": "x"},
            ],
            [None],
        ),
        (
            [
                {"time": 0, "kind": "set", "key": "__proto__", "value": "", "ttl": 2},
                {"time": 1, "kind": "get", "key": "__proto__"},
            ],
            [""],
        ),
        (
            [
                {"time": 0, "kind": "set", "key": "x", "value": 1, "ttl": 1},
                {"time": 1, "kind": "set", "key": "x", "value": 2, "ttl": 5},
                {"time": 2, "kind": "get", "key": "x"},
            ],
            [2],
        ),
    ],
    CACHE_DRIVER,
)

add(
    "shell-line-records",
    "shell",
    "The script reads stdin and prints each nonempty record unchanged with a final newline. "
    "Strip a single trailing CR for CRLF input. Preserve spaces and backslashes, and process "
    "the final unterminated record. Use portable Bash 3.2 syntax.",
    'while read line; do [ -n "$line" ] && echo $line; done\nexit 0',
    'while IFS= read -r line || [ -n "$line" ]; do\n line=${line%$\'\\r\'}\n [ -z "$line" ] || printf \'%s\\n\' "$line"\ndone\nexit 0',
    [
        ({"stdin": "a\nb", "args": []}, {"code": 0, "stdout": "a\nb\n"}),
        ({"stdin": " a \\b \n", "args": []}, {"code": 0, "stdout": " a \\b \n"}),
        ({"stdin": "", "args": []}, {"code": 0, "stdout": ""}),
        ({"stdin": "\r\na\r\n\n", "args": []}, {"code": 0, "stdout": "a\n"}),
        ({"stdin": "-n\n", "args": []}, {"code": 0, "stdout": "-n\n"}),
        ({"stdin": "  ", "args": []}, {"code": 0, "stdout": "  \n"}),
    ],
)

add(
    "shell-argument-boundary",
    "shell",
    "Parse [-n value] [--] operands. -n requires a following nonempty decimal digit string; "
    "default 1. Before --, unknown options and missing/invalid -n values exit 2 with no stdout. "
    "The first non-option ends option parsing. Print n then each remaining operand on its own "
    "line, preserving spaces, wildcard characters and leading dashes. Bash 3.2 compatible.",
    'n=1\nif [ "$1" = -n ]; then n=$2; shift 2; fi\necho $n\nfor arg in $@; do echo $arg; done',
    """
n=1
while [ "$#" -gt 0 ]; do
 case "$1" in
  -n) [ "$#" -ge 2 ] || exit 2; case "$2" in ''|*[!0-9]*) exit 2;; esac; n=$2; shift 2;;
  --) shift; break;;
  -*) exit 2;;
  *) break;;
 esac
done
printf '%s\n' "$n"
for arg in "$@"; do printf '%s\n' "$arg"; done
""",
    [
        (
            {"stdin": "", "args": ["-n", "2", "a b", "*"]},
            {"code": 0, "stdout": "2\na b\n*\n"},
        ),
        ({"stdin": "", "args": ["--", "-x"]}, {"code": 0, "stdout": "1\n-x\n"}),
        ({"stdin": "", "args": ["-n"]}, {"code": 2, "stdout": ""}),
        ({"stdin": "", "args": ["-n", "-1"]}, {"code": 2, "stdout": ""}),
        ({"stdin": "", "args": ["-z"]}, {"code": 2, "stdout": ""}),
        (
            {"stdin": "", "args": ["a", "-n", "3"]},
            {"code": 0, "stdout": "1\na\n-n\n3\n"},
        ),
    ],
)

add(
    "shell-file-bytes",
    "shell",
    "Print the total byte count of all filename arguments followed by a newline. Filenames "
    "may have spaces, globs or leading dashes. No args gives 0. Any nonexistent file or directory "
    "argument exits 2 and prints nothing. Do not create or modify files; Bash 3.2 compatible.",
    "total=0\nfor f in $@; do n=$(wc -c < $f); total=$((total+n)); done\necho $total",
    'total=0\nfor f in "$@"; do [ -f "$f" ] || exit 2; n=$(wc -c < "$f") || exit 2; total=$((total+n)); done\nprintf \'%s\\n\' "$total"',
    [
        (
            {"stdin": "", "args": ["data/a b.txt", "data/x.txt"]},
            {"code": 0, "stdout": "7\n"},
        ),
        ({"stdin": "", "args": []}, {"code": 0, "stdout": "0\n"}),
        ({"stdin": "", "args": ["data/*"]}, {"code": 0, "stdout": "1\n"}),
        ({"stdin": "", "args": ["data/x.txt", "missing"]}, {"code": 2, "stdout": ""}),
        ({"stdin": "", "args": ["data"]}, {"code": 2, "stdout": ""}),
        ({"stdin": "", "args": ["-dash"]}, {"code": 0, "stdout": "2\n"}),
    ],
    setup="file-bytes",
)

add(
    "shell-filename-stem",
    "shell",
    "For each argument, print its basename with only the final extension removed. Preserve "
    "dotfiles without another dot (.env stays .env), remove a trailing dot, and preserve all "
    "other bytes including spaces, backslashes, wildcard characters and dashes. Bash 3.2 compatible.",
    "for p in $@; do p=${p##*/}; echo ${p%%.*}; done",
    """
for p in "$@"; do
 p=${p##*/}
 case "$p" in
  .*) rest=${p#.}; case "$rest" in *.*) p=${p%.*};; esac;;
  *.*) p=${p%.*};;
 esac
 printf '%s\n' "$p"
done
""",
    [
        ({"stdin": "", "args": ["dir/a.tar.gz"]}, {"code": 0, "stdout": "a.tar\n"}),
        ({"stdin": "", "args": [".env"]}, {"code": 0, "stdout": ".env\n"}),
        ({"stdin": "", "args": ["a b.txt", "-n"]}, {"code": 0, "stdout": "a b\n-n\n"}),
        (
            {"stdin": "", "args": [".config.json", "x."]},
            {"code": 0, "stdout": ".config\nx\n"},
        ),
        (
            {"stdin": "", "args": ["plain", "a\\b.ext", "*.txt"]},
            {"code": 0, "stdout": "plain\na\\b\n*\n"},
        ),
        ({"stdin": "", "args": []}, {"code": 0, "stdout": ""}),
    ],
)

ORDER_SCHEMA = "CREATE TABLE customers(id INTEGER PRIMARY KEY, name TEXT); CREATE TABLE orders(id INTEGER, customer_id INTEGER, amount INTEGER, status TEXT);"
add(
    "sql-paid-totals",
    "sql",
    "Return customer id and total paid amount, including customers with no paid orders as zero. "
    "Schema: customers(id,name); orders(id,customer_id,amount,status). Only status='paid' counts. "
    "Order by customer id; do not change the database.",
    "SELECT c.id, SUM(o.amount) FROM customers c JOIN orders o ON o.customer_id=c.id WHERE o.status='paid' GROUP BY c.id ORDER BY c.id;",
    "SELECT c.id, COALESCE(SUM(o.amount),0) FROM customers c LEFT JOIN orders o ON o.customer_id=c.id AND o.status='paid' GROUP BY c.id ORDER BY c.id;",
    [
        (
            {"customers": [[1, "a"], [2, "b"]], "orders": [[1, 1, 10, "paid"]]},
            [[1, 10], [2, 0]],
        ),
        ({"customers": [[1, "a"]], "orders": [[1, 1, 5, "pending"]]}, [[1, 0]]),
        ({"customers": [], "orders": []}, []),
        (
            {
                "customers": [[2, "b"], [1, "a"]],
                "orders": [[1, 1, 4, "paid"], [2, 1, 6, "paid"], [3, 2, -2, "paid"]],
            },
            [[1, 10], [2, -2]],
        ),
        ({"customers": [[1, "a"]], "orders": [[1, 99, 100, "paid"]]}, [[1, 0]]),
        (
            {
                "customers": [[1, "a"]],
                "orders": [[1, 1, 0, "paid"], [2, 1, 50, "cancelled"]],
            },
            [[1, 0]],
        ),
    ],
    setup=ORDER_SCHEMA,
)

add(
    "sql-latest-event",
    "sql",
    "Return (user_id,id,value) for each user's latest event. Schema events(id,user_id,ts,value). "
    "Largest ts wins, breaking ties by largest id. Return exactly one per user ordered by user_id. "
    "Do not change the database.",
    "SELECT user_id, id, value FROM events GROUP BY user_id HAVING ts=MAX(ts) ORDER BY user_id;",
    "SELECT user_id,id,value FROM (SELECT *,ROW_NUMBER() OVER(PARTITION BY user_id ORDER BY ts DESC,id DESC) AS rn FROM events) WHERE rn=1 ORDER BY user_id;",
    [
        ({"events": [[1, "a", 1, "old"], [2, "a", 1, "new"]]}, [["a", 2, "new"]]),
        ({"events": [[2, "a", 2, "new"], [1, "a", 1, "old"]]}, [["a", 2, "new"]]),
        ({"events": []}, []),
        (
            {"events": [[4, "b", 1, "b"], [3, "a", 2, "a"]]},
            [["a", 3, "a"], ["b", 4, "b"]],
        ),
        (
            {"events": [[3, "a", 1, None], [2, "a", 1, "x"], [1, "a", 0, "z"]]},
            [["a", 3, None]],
        ),
        ({"events": [[99, "a", 1, "x"], [1, "a", 2, "y"]]}, [["a", 1, "y"]]),
    ],
    setup="CREATE TABLE events(id INTEGER,user_id TEXT,ts INTEGER,value TEXT);",
)

add(
    "sql-null-antijoin",
    "sql",
    "Return ids from users(id) having no row with matching user_id in subscriptions(user_id). "
    "A subscription user_id may be NULL and must not exclude everyone. Return unique ids sorted "
    "ascending. Do not change the database.",
    "SELECT id FROM users WHERE id NOT IN (SELECT user_id FROM subscriptions) ORDER BY id;",
    "SELECT DISTINCT u.id FROM users u WHERE NOT EXISTS (SELECT 1 FROM subscriptions s WHERE s.user_id=u.id) ORDER BY u.id;",
    [
        ({"users": [[1], [2]], "subscriptions": [[None], [1]]}, [[2]]),
        ({"users": [[1], [2]], "subscriptions": [[1]]}, [[2]]),
        ({"users": [], "subscriptions": [[None]]}, []),
        ({"users": [[2], [1], [2]], "subscriptions": []}, [[1], [2]]),
        ({"users": [[1]], "subscriptions": [[1], [1]]}, []),
        ({"users": [[0], [-1]], "subscriptions": [[None], [99]]}, [[-1], [0]]),
    ],
    setup="CREATE TABLE users(id INTEGER); CREATE TABLE subscriptions(user_id INTEGER);",
)

add(
    "sql-dense-ranking",
    "sql",
    "Return (team,player,points,rank) for players(team,player,points). Rank distinct point totals "
    "descending within each team using dense ranks starting at 1. Ties share rank without gaps. "
    "Order rows by team, rank, player. Do not change the database.",
    "SELECT team,player,points,RANK() OVER(PARTITION BY team ORDER BY points DESC) AS r FROM players ORDER BY team,r,player;",
    "SELECT team,player,points,DENSE_RANK() OVER(PARTITION BY team ORDER BY points DESC) AS r FROM players ORDER BY team,r,player;",
    [
        (
            {"players": [["a", "x", 10], ["a", "y", 10], ["a", "z", 5]]},
            [["a", "x", 10, 1], ["a", "y", 10, 1], ["a", "z", 5, 2]],
        ),
        (
            {"players": [["a", "x", 1], ["b", "y", 2]]},
            [["a", "x", 1, 1], ["b", "y", 2, 1]],
        ),
        ({"players": []}, []),
        (
            {"players": [["a", "z", 0], ["a", "x", 0], ["a", "y", -1]]},
            [["a", "x", 0, 1], ["a", "z", 0, 1], ["a", "y", -1, 2]],
        ),
        (
            {"players": [["b", "x", 2], ["a", "y", 9], ["b", "y", 3]]},
            [["a", "y", 9, 1], ["b", "y", 3, 1], ["b", "x", 2, 2]],
        ),
        (
            {"players": [["a", "a", 5], ["a", "b", 4], ["a", "c", 4], ["a", "d", 3]]},
            [["a", "a", 5, 1], ["a", "b", 4, 2], ["a", "c", 4, 2], ["a", "d", 3, 3]],
        ),
    ],
    setup="CREATE TABLE players(team TEXT,player TEXT,points INTEGER);",
)

BY_NAME = {task.name: task for task in TASKS}
