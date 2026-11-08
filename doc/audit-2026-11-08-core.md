# Core optimizer parity audit — 2026-11-08

## Status and evidence standard

Owner: core-opt; task-1. Baseline port HEAD 938fc19, vendor HEAD 661ceb22. All eleven assigned upstream implementation files and all scoped production MoonBit files have been read completely. This is a declaration-level source audit, NOT a claim of exhaustive input coverage. Tests and remaining hypotheses are being integrated; task remains in progress. Lead subsequently authorized bounded repairs in cfg/ssa/mem/fold/ifopt/gvn plus audit_core corpus. No vendor changes, no global formatter/info/build, no lexer/parser changes by this agent. Initial unrelated dirty files were lexer/lexer.mbt, lexer/lexer_wbtest.mbt, parser/func.mbt, parser/parser_wbtest.mbt and parser/variadic_wbtest.mbt.

Skills loaded: using-superpowers (subagent exception), moonbit, moonbit-agent-guide, moonbit-orientation, systematic-debugging, verification-before-completion, test-driven-development. AGENTS.md read. Prior AUDIT-LEDGER.md read only as leads; several claims are contradicted below.

## Confirmed defects repaired so far

All baseline lines below refer to pre-edit source. Each fix had an observed failing test first. Logs in build/audit-core-opt; isolated build dir explicitly approved by lead.

1. **Lost symbol type in alias analysis**: cfg/alias.mbt:57 writes zero instead of C alias.c:21 complete `c->sym`. `check_alias` consequently treats equal label/different thread or extern modifiers as MustAlias instead of MayAlias. Repair copies c.sym_type. Tests: alias preserves symbol type; distinguishes same name different symbol type.
2. **Lost symbol type on reconstructed load**: ssa/load.mbt:168 writes zero instead of load.c:157 `c.sym=a->u.sym`. Repair preserves a.sym_type. Direct LLoad+ASym regression failed 0!=1 then passed.
3. **Address subtraction ignores symbol type**: gvn/gvn.mbt:380 compares only label, unlike fold.c:50 symeq (util.c:469 includes type and id). `sub thread $symbol,$symbol` was folded to zero; vendor retains Sub. Repair compares sym_type too. Corpus test/audit_core_sym_sub.ssa; -dG outputs match after repair.
4. **If-conversion speculates writes**: handwritten ifopt/ifopt.mbt:61–90 pinned table omitted blit pair and extension side effects. Exactly two blit ops pass MaxIns=2 and get moved unconditionally to start. C ifopt uses gcm pinned. Repair exposes existing gvn.pinned and uses it from ifopt; no duplicate flag algorithm. Corpus test/audit_core_if_blit.ssa; vendor keeps Jjnz, baseline removed it. Functional invariant: when c=0 no source read or destination write may occur, even if pointers are invalid. -dK now matches vendor.
5. **Comparison width omitted**: ssa/use.mbt omitted ssa.c:86–87 cmp=>Wub. Repair restores contiguous comparison range check; width unit failed then passed.
6. **Neg not cheap**: gvn/gcm.mbt:43–54 omitted gcm.c:362 Oneg, suppressing upstream sink behavior. Repair restores Neg.
7. **Eliminated phi sentinel indexed before checked**: gvn/gvn.mbt:859 reads phi_visit[-1] when p.to=RNone, unlike copy.c:81 guard. Direct recorded eliminated UPhi causes SIGABRT. Repair checks p.to.is_none first.
8. **Stale generated pinned table**: gvn/op_pinned_gen.mbt lacked 8 subword par/arg ops, despite ops.h pinning all. Existing generator tools/gen_op_pinned.py already supports them. Regenerated after test failed; no generator edits. Normal abi0 removes these, but public passes must preserve internal semantics.
9. **Missing load rebase**: entire load.c:169–184 function and call at452 absent from ssa/load.mbt. Equivalent `%p+4` refs on opposite sides after a store merge generated duplicate load phis instead of reusing one slice phi. Exact rebase restored: only RTmp, signed-short-representable offset, ALoc/AEsc/AUnk; return new Slice value to preserve C value-copy semantics. test/audit_core_rebase.ssa baseline diff has extra ld.2 phi; direct test failed 2!=1.
10. **Missing blit grouping**: gvn/gcm.mbt igroup lacked util.c:265–272 pair groups. Restored both starting-half cases; direct regression failed (0,1)!=(0,2). Both halves must remain adjacent through dependency scheduling.
11. **GVN table copied instead of retained identity**: gvn/gvn.mbt:1242 stored ins_copy versus gvn.c:62 `gvntbl[idx]=i`; rebuildcfg:1679 used structural ins_eq versus C pointer equality at454. Restored reference storage and physical_equal on mutable Ins objects. Test mutating original operand failed to reflect through table before fix. Full integration implications still under final verification.

First RED: 8 tests,0 pass,8 fail (red.log); first GREEN8/8. Second batch RED: sentinel panic; pinned1/1 fail; rebase2!=1; group tuple mismatch; reference identity false. GREEN2:13/13. Initial RED attempt had test-fixture immutable Con errors, corrected using Con::addr_sym; another attempt overlapped lead parser edit and failed parser/data.mbt syntax, not counted as regression evidence.

## Complete production declaration inventory (source-read coverage)

Legend: V = compared all branches to named C counterpart on valid IR; D = divergence described above/below; A = representation adaptation; X = port-only/dead historical implementation without counterpart in vendored revision. Static data/struct fields are included, not only public functions.

### cfg/cfg.mbt and cfg/simplcfg.mbt versus cfg.c

- fillpreds/addpred -> fillpreds (two passes count then append; same link order, duplicate successor guard): V/A.
- porec -> rpo_dfs: V/A (-2 visiting marker versus0, same visited test; stable ids separate from rpo_id).
- fillrpo -> fillrpo: V/A (keep dead block storage, prune def_order; eagerly removes dead predecessor phi args).
- fixphis, fillcfg -> same: V (edge membership, reachable sentinel, nonempty invariant).
- inter -> dom_inter: V; filldom -> filldom: V (same predecessor fixed point and reverse definition-order child linking).
- sdom -> sdom: V/A (negative guard); dom -> ssa.dom/gvn.dom_b/ssa.dominates: V duplicated helpers.
- addfron -> add_frontier; fillfron; loopmark->loop_mark; loopiter; multloop/fillloop -> fillloop closure: V.
- uffind->uf_find; simpljmp: V/A (ret storage id may differ from RPO but union find sized to full storage; appended only after old chain processed).
- filldepth/lca -> gvn.gcm_filldepth/depth_rec/lca_bid: A, see GCM.
- reachrec/reaches/reachesnotvia -> GVN same names: V/A (full storage length bounds, visit reset includes dead storage).
- ifgraph -> ifopt.ifgraph: V (RPO swap tracks then/else outputs, all triangle/diamond branches).
- struct Jmp(type,arg,s1,s2), jmpeq,jmpnophi,simplcfg -> parallel arrays jtype/jarg/js1/js2, helper funcs and simplcfg: D/A. Whole-Jmp copy source index captured; extra alias/dead arrays avoid altering stable ids. Final call is fillrpo+fillpreds, not C fillcfg (remaining gap).
- addins/addbins/phiargn/phiarg: compared util.c 158/167/422; appends reference versus C copy (remaining identity question for simplcfg); missing phiargn returns -1 instead of abort.
- remove_phi_arg/edgedel: X historical SCCP support; no counterpart in current cfg.c.
- newblk -> types.Blk::new/Fn::add_blk is cross-domain dependency (types owner), not missing cfg implementation.

### cfg/alias.mbt versus alias.c

AliasResult(MustAlias,MayAlias,NoAlias), getalias, check_alias, escapes, esc, store_mask/store, fillalias, is_alloc: all read. check_alias ordering and 64-bit signed offsets match; Int64 delta safely narrowed only in overlapping load branch (sizes bounded2^28). getalias clones AliasInfo, necessary because offset adjustment must not mutate source. Symbol field defect repaired. Slot identity uses tmp index; stack escape dynamically consults base slot. fillalias preserves alloc size [-1,0..64], byte mask, blit pair skip/store, argc exception, Jretc guard. Remaining: missing ABot reset (C144–145), final phi scan traverses dead blks not def_order. C itself does not reset union mask between successive calls; do not invent reset beyond C.

### ssa/ssa.mbt, use.mbt, ssacheck.mbt, elimsb.mbt versus ssa.c/util.c/abi.c

- adduse->adduse: A index+arg_num instead of variadic pointers; no-use hardware tmp suppression differs (normally not encountered pre-isel).
- filluse: V/D (cmp width repaired; cls reset Kx vs C0; no Tmp.def because per-consumer def_idx).
- kx, clsmerge, phicls, loadsz, storesz: V; loadsz invalid fallback0/storesz fallback8 rather than C abort.
- refindex: V; Name(r,blk_id,up) and NamePool(entries,free), new,np_alloc,np_free versus Name(r,b,up)/namel/nnew/nfree: A GC plus indices/free stack, no observable name order change.
- phiins: D single-definition !live-out special case avoids C newtmp; all other worklist LIFO, liveness, class merge, frontier visitation and prepend order compared.
- rendef/getstk/renblk/ssa -> ren_dfs/getstk/renblk + pipeline filldom/fron/live/phiins: V/A inlined rendef repeated, lazy dominance pops and visit original-id mapping preserved.
- sdom/dom, phicheck, ssacheck: V/A indexes implement address ordering; diagnostics all CompileError instead of C visit-dependent ICE distinction.
- elimsb: V with abi.c; walks dead retained storage too (safe because not used).
- ssa/memopt.mbt load_to_ext,use_ins,memopt: duplicate historical promote; core algorithm transcribed, but old diagnostic Ice. Production uses mem.promote; tests often use memopt instead.

### ssa/load.mbt versus load.c

LocType(LRoot,LLoad,LNoLoad); Loc(kind,off,blk); Slice(r,off,sz,cls); Insert(isphi,num,bid,rpo_id,off,ins,phi_m,phi_p); LoadState(fn_,inum,ilog,nlog): A disjoint union storage, mutable locals cloned when C copies Loc/Slice; insertion counters32-bit signed vs C uint31-bit num, realistic bounds same.

MASK->mask_of; iins; cast; mask; load; rebase (now added); killsl; def; icmp; loadopt fully compared. load_abort is C goto-Load rollback factored out; restores tmp/log lengths, not monotone insertion number just like C. dominates is C assertion helper. def all Must/May/NoAlias arms, blit offset slicing, shift/mask reconstruction, recursive remainder, memo-phi, kill bases, single/multi predecessors and load-placement permissions compared. Missing rebase and sym bits fixed. Remaining: comparator imposes num ordering for equal-block phis (C returns0), and phi insert increments inum though C does not. Must avoid replacing algorithm with alternative CSE.

### mem/promote.mbt, mem.mbt, coalesce.mbt versus mem.c

- promote: D default behavior silently skips read-only slot (C errors), plus optional skip_read_before_write for C frontend. Rest of candidate use validation, width/class matching, zero-use removal, store-to-copy, load extension/cast handling V.
- loadsz/storesz/load_to_ext: duplicates V valid paths; AliasL(kind,base,offset,slot,sz,m), alias_default,alias_copy,load_alias_from_fn: A snapshot subset; no second alias algorithm (file header stale). alias_copy unused.
- Range(a,b), range_new,rin,rovlap,radd: V. StoreRec(ip,blk,idx) maps Store(ip,i); Slot(t,sz,m,l,r,s,st,nst) fields all mapped; -1 fusion index is null Slot*.
- slot_of/slot, slot_load/load, slot_store/store: V with shl_bits out-of-range shift deviation (C UB; not automatically bug).
- scmp,sort_slots; maxrpo->closure/max_loop: V/A; local max_loop avoids destructively reusing loop_depth, upstream later fillloop overwrites.
- set_nop,copy_ins_fields,fmt_space3: V for upstream Ins fields (extension asm_text left stale; only alloc defs copied here).
- coalesce: all collection, reverse-RPO byte liveness/IP pre/post decrement, loop range extension, dead store/blit-pair removal, dead dependency stack, size-order fusion, overlap checks, earliest alloc-def transplant, uses rewrite, fusion target based blit direction/identity, stats/debug branches read. No new confirmed semantic fault found on valid bounded slot accesses.

### fold/ versus fold.c

Current fold.c only has iscon,foldint,foldflt,opfold,foldref; production equivalents are in gvn/gvn.mbt (below). fold/fold.mbt is old SCCP, not a transcription of current revision, and production pipeline does not call it. Still public and used by several test helpers. Read all: BOT/TOP, Edge(dest,dead), FoldState(fn_,val,edges,usewrk,nuse,work), czero,latval,latmerge,update,deadedge,visitphi,visitins,visitjmp,visit_blk,renref,fold. X; risks: hardcoded zero index0, TOP indexing/renref handling.

fold/opfold.mbt: is_word_cmp,is_long_cmp,is_single_cmp,is_double_cmp,sext32,zx32_fold,con_double,con_single,foldint,foldflt,opfold all read. D: address add/sub loses sym_type and subtraction tests only label; opfold misses narrow result mask C216–217; signed/unsigned int64->Float via Double may double-round unlike direct C. Non-finite/out-of-range float-int conversion not portable C semantics.

### ifopt/ versus ifopt.c/simpl.c

max_ins/max_phis,sel0_op/sel1_op,block_order,is_div_wl/pinned,okbranch,okjoin,ifgraph,okgraph,phiarg,addins,addbins,convert,class_char,jump_name,dump_fn,ifconvert: all read. Structural tests and select source order V; pinned duplicate replaced with shared predicate. dump_fn duplicates parser printer, stale no-Sel comments; full debug payload equivalence not assumed. convert instruction refs remain aliases in dead blocks (A under immediate fillcfg).

ulog2_tab64/ulog2/ispow2, blit, simpl_ins/ins,simpl: V for all 64 deBruijn entries, zero size, signed copy direction, 8/4/2/1 chunks and reverse emission. Handwritten table exists despite generator rule; no differing entry. Int32 sz vs signed Ref29 cap considered. In-place backward expansion retains source order and newtmp order; invalid broken pair silently retained instead of C assertion.

### gvn/gvn.mbt versus gvn.c/copy.c/fold.c

- con01; rtype_of/rval_of; ins_copy,nop_ins: A (RNone separate tag; raw C Ref val bitfields differ for negative RInt but these ops pinned).
- op_commutes,op_assoc,op_hasid,op_idval,op_idemp,op_cmpeqwl,op_cmplgtewl,op_eqval: V all entries manually compared ops.h; hand-maintained tables still drift risk. is_word_cmp/is_long_cmp/is_single_cmp/is_double_cmp/is_cmp_op,argcls,isconbits: V valid ops.
- ExtInfo(zext,nopw,usew), ext_of/ext,bitwidth,extcpy_width/extcpy: V tables and integer widths all checked.
- sext32,low32u,con_single,con_double,c_iscon/iscon,c_foldint/foldint,c_foldflt/foldflt,c_opfold/opfold,foldref: V/D symbol subtraction fixed; arithmetic wrap, div-by-zero, signed-min/-1 guard, Kw truncation, signed/unsigned compares, shifts31|w<<5 all matched; float-single conversion double-round risk remaining. c_foldflt invalid address returns None vs C err.
- GState(fn_,tbl,def_idx,phi_visit),new,build_def_idx,clear_phi_visit,find_phi,phiarg: A side-table mapping; phi_visit keyed tmp destination; removed sentinel bug fixed.
- dwl,defwidthle,uwl,usewidthle,isw1: V with visit clear before vs C after (equivalent isolated queries; all callers use wrappers). char ext widths widened to Int32 safely.
- gvn_adduse,replaceuse,replaceuses,killins: V/A stable index uses; nuse truncation ignores stale tail.
- rcmp,sdom_b,dom_b,reachrec,reaches,reachesnotvia,branchdom,domzero,cmpeqz,zeroval,usecls,propjnz0: V valid IR; block identity versus rpo_id consistently mapped.
- mix,ref_hash,ins_hash,ins_eq,gvndup: V/D hash wraps32, modulo interpreted unsigned; identity copy defect fixed.
- negcon,normins,assoccon: V same operation guards and width/constant conversion, temporary-def side table valid in loop.
- phieq,phicopyref,copyref,dedupphi,dedupins,dedupjmp: V/A eliminated phi records retained until pass end to keep uses indexed; phicopyref skips removed predecessors; full conditional and class-width branches checked.
- narrowpars: A moving use indices by npar necessary; old C instruction arena pointer behavior otherwise copied.
- rebuildcfg: D identity fixed; dead instructions copied to start in old RPO order.
- gvn: V prologue order including narrowpars before filluse and ssacheck; minimum table length1 harmless empty fn adaptation; deleted phi removal deferred.

### gvn/gcm.mbt versus gcm.c (and cfg.c/util.c helpers)

isdivwl,op_pinned,pinned,canelim,isalloc_op,cheap; GcmState(fn_,depth,gcmbid,def_idx,sinkbuf),new,gcmbid_get/set,gcm_def_idx; depth_rec,gcm_filldepth; earlyins,schedearly,earlyblk; lca_bid,bestbid,lateins,latephi,latejmp,schedlate,lateblk; add_one,addgcmins,gcmmove; sinkref,sink; igroup,schedins,schedblk,gcm: all read.

- depth is side table indexed stable block id, recursion instead of C iterative path backfill (same valid dominator result, different stack bound). -1 gcmbid corresponds NOBID.
- early mark uses literal0 not start_id (normal parser start0; programmatic nonzero-start concern remains).
- early/late dependency direction, pinned-use roots, canelim recursion, lowest-loop-depth placement and edge-specific phi uses V.
- defer physical phi deletion until late scheduling ends: necessary safe adaptation for indexed UPhi references.
- gcmmove snapshots before nop, def maps rebuilt after each filluse: V.
- sinkref pushes COPY before recursively mutating local Ins args: matches C emiti(i) by value before local recursion (do not “fix” it to link recursive replacements).
- schedins omits nops because C addins skips Onop too; previous ledger characterization of C keeping placeholders inaccurate.
- missing Neg cheap and blit grouping fixed. Public gcm extra fillrpo/pred/dom/use before C filldepth/loop may alter order; no valid-output difference yet established.
- op_pinned_generated: all fields/arms inspected versus ops.h and existing generator; eight stale arms fixed by regeneration.

## Remaining actionable work / unresolved gaps

- Finish support-test reads and run all scoped package suites; no scoped production declaration left unread.
- Observe and fix stale fold CON_Z=0 exposed by types owner restoring UNDEF0/zero1; assess old SCCP actual callers.
- Equal-phi comparator nonzero versus C0: explicit regression and exact restoration needed (ordering not semantic evaluation, but algorithm parity).
- mem.promote read-only slot rejection: needs normal path CompileError without breaking opt-in C frontend compatibility; coordinate raise signature if changed.
- cfg.simplcfg final fillcfg missing and extra alias walk, stale deleted-block alias phi escapes, SSA single-def rename deviation: demonstrate concrete reachable discrepancy before edits.
- float conversion double rounding: construct exact halfway integer, verify vendor and port; do not generalize C UB to portable expected result.
- GVN eliminated-phi safety after fix needs real pipeline trigger beyond direct helper test.
- Dynamic coverage of every branch is not claimed. Broad oracle corpus and multiple backend checks pending lead coordination; current tests prove listed invariants only.
