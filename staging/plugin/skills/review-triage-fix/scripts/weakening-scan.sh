#!/bin/bash
# review-triage-fix: anti-test-weakening detector (heuristic, report-only).
# Input: a unified diff on stdin. Output: "CLEAN" or one or more
#   WEAKENED<TAB><file><TAB><reason>
# Heuristic on purpose (design §7-B). No auto-revert. Always exits 0.
awk '
function is_test(p){ return (p ~ /(^|\/)tests?\//) || (p ~ /(^|\/)spec\//) \
  || (p ~ /test_[^\/]*\.[a-zA-Z]+$/) || (p ~ /_test\.[a-zA-Z]+$/) \
  || (p ~ /\.test\.[a-zA-Z]+$/) || (p ~ /\.spec\.[a-zA-Z]+$/) \
  || (p ~ /Tests?\.[a-zA-Z]+$/) }
function flush(){
  if(file!="" && testf){
    if(deleted) print "WEAKENED\t" file "\tdeleted-test-file"
    else {
      if(skipadd>0)            print "WEAKENED\t" file "\tskip/xfail-added"
      if(asrt_rm>asrt_add)     print "WEAKENED\t" file "\tassert-removed (" asrt_rm ">" asrt_add ")"
      if(defrm>0 && defadd==0) print "WEAKENED\t" file "\ttest-removed-or-commented"
    }
  }
}
/^diff --git / { flush(); file=""; testf=0; deleted=0; skipadd=0; asrt_rm=0; asrt_add=0; defrm=0; defadd=0; next }
/^deleted file mode/ { deleted=1; next }
/^\+\+\+ / { p=$2; sub(/^b\//,"",p); if(p!="/dev/null") file=p; testf=is_test(file); next }
/^--- /    { if(file==""){ p=$2; sub(/^a\//,"",p); file=p; testf=is_test(file) } next }
{
  if(!testf) next
  line=$0
  if(substr(line,1,1)=="-" && substr(line,1,3)!="---"){
    b=substr(line,2)
    if(b ~ /assert|expect\(|XCTAssert|EXPECT_|ASSERT_|require\.|should|t\.Error|t\.Fatal/) asrt_rm++
    if(b ~ /(def|func|fn)[ \t]+[Tt]est|[ \t]it\(|[ \t]test\(|@Test/) defrm++
  } else if(substr(line,1,1)=="+" && substr(line,1,3)!="+++"){
    a=substr(line,2)
    if(a ~ /assert|expect\(|XCTAssert|EXPECT_|ASSERT_|require\.|should|t\.Error|t\.Fatal/) asrt_add++
    if(a ~ /(def|func|fn)[ \t]+[Tt]est|[ \t]it\(|[ \t]test\(|@Test/) defadd++
    if(a ~ /@pytest\.mark\.(skip|xfail)|\.skip\(|\.only\(|xit\(|xdescribe\(|t\.Skip\(|@Disabled|@Ignore|@unittest\.skip/) skipadd++
  }
}
END{ flush() }
' | { out=$(cat); [ -z "$out" ] && echo "CLEAN" || printf '%s\n' "$out"; }
exit 0
