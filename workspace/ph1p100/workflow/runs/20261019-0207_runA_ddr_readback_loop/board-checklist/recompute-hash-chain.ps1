$ErrorActionPreference='Stop'
$root=(Get-Location).Path
$run=Join-Path $root 'workflow\runs\20261019-0207_runA_ddr_readback_loop'
$wt=Join-Path $root 'upstream\ph1p100-pcie-ep-fpga-wt0207'
$out=Join-Path $run 'board-checklist'
$logFile=Join-Path $out 'hash-chain-recompute.txt'
$log=New-Object System.Collections.Generic.List[string]
$mism=0;$miss=0;$total=0
function W([string]$s){ [void]$script:log.Add($s) }
function P([string]$s){ Write-Output $s }
try {
  $hadRoot=Test-Path 'D:\anlogic\runa_runC'
  $stage=$null;$reuse=$false
  if($hadRoot){
    $cand=@(Get-ChildItem 'D:\anlogic\runa_runC' -Directory | Sort-Object Name)
    if($cand.Count -eq 1){
      $inner=@(Get-ChildItem $cand[0].FullName -Force)
      if($inner.Count -eq 0){ $stage=$cand[0].FullName; $reuse=$true }
    }
  }
  if(-not $stage){
    $ts=Get-Date -Format 'yyyyMMdd_HHmmss'
    $stage='D:\anlogic\runa_runC\'+$ts
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
  }
  W ('generated_at='+(Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz'))
  W ('root='+$root)
  W ('stage='+$stage+'|reused_empty_dir='+$reuse+'|runa_runC_existed_before='+$hadRoot)

  $ent=New-Object System.Collections.ArrayList
  function AE($p,$exp,$bytes,$grp){ [void]$ent.Add([pscustomobject]@{p=$p;exp=$exp;bytes=$bytes;grp=$grp}) }
  AE 'checker-integrate\candidate.diff' '5907b38f6241d3dcc163eeaeb78d67941c8ab0c2967b6d66edf5c8c1c6e18cb2' 59091 'P1'
  AE 'checker-integrate\candidate-manifest.json' '68ab235e9c593e60edd08ede176c77d83082a9423e5920fab78c195188d167bd' 9368 'P1'
  AE 'checker-integrate\geometry-audit.md' 'cbeb883c25eda5bd02ac69b818b7985e32767a9cfd98a352746f8cde40081775' 2630 'P1'
  AE 'checker-integrate\dev-result.md' '4ea13bd32329079ca80e5735976c0c84a3546eed7e94d4d5439acec7fccc3379' 7370 'P1'
  AE 'checker-integrate\regression-summary.txt' 'e1f8d5474a325287a4dd7fe800c4212cb4a600074be152f5e48c0ac0f2c9efec' 553 'P1'
  AE 'build\candidate-manifest.json' '0f67d299' 16523 'P2'
  AE 'build\preflight-processes.txt' '6dfbc9667b3cc130519f9e069c3df3cab269c786cf4cc32f7702a113eda8b67a' 326 'P2'
  AE 'build\cwc-check.txt' 'aa11e9ced36dcf77dd47888d5e2ed0265d8d6ef8e6fcc83bde86aa445e5931a1' 13920 'P2'
  AE 'build\cwc-multipiece-map.json' '821fea4a7d0bc2598ddc959b4f17334a130d436debda1bd60043752503c2c2d8' 71298 'P2'
  AE 'build\cwc-strict-check.txt' 'a70f50c4d9781f8c686f2835443d0fbb84b1d7d94e90efb06030df83f2df4baf' 206 'P2'
  AE 'build\prj\commands.log' '104d9e0c4a626a4ac5760cbdfae42e2b18f1b2fd8c2be531671de018a0c6301c' 245 'P2'
  AE 'build\prj\td_00_all_debug.log' '6e072340a0bfdb2579105864f6efabbc1d977a90319ecf5a3de62d3afe4a4209' 26822 'P2'
  AE 'build\prj\ph1p_pcie_integration_Runs\phy_1\ph1p_pcie_integration.bit' '5b67a8f5925327ba9d0442d9e4228fcfd254c80a2f86d921ceda70ecae111d52' 5224027 'P2'
  AE 'build\prj\ph1p_pcie_integration_Runs\phy_1\cw\compiled.bit' '5b67a8f5925327ba9d0442d9e4228fcfd254c80a2f86d921ceda70ecae111d52' 5224027 'P2'
  AE 'build\prj\ph1p_pcie_integration_Runs\phy_1\cw\compiled.cwc' '8dda54d4efa8e6be728a6ebb34686f25de90a36b039eda6f831dfb9c346c664f' 143444 'P2'
  AE 'build\prj\ph1p_pcie_integration_Runs\phy_1\cw\auto_created_cwc1\auto_created_cwc1_watcherInst.sv' 'd113814447aae6168ed7f1ff9c3bff875c77237a774e3598856ba43508665641' 2144 'P2'
  AE 'build\prj\ph1p_pcie_integration_Runs\phy_1\ph1p_pcie_integration_inst.bid' 'a068e42e50b2d9d9ced1ae85f9cfa9e272bbce99ae83192ca7fc930af9ecf1db' 151492 'P2'
  AE 'build\prj\ph1p_pcie_integration_Runs\phy_1\final_timing.rpt' '778ed03810539a2ae7927a6540492b375e362d873b0f6ef6f8f8c256c179e64c' 5465590 'P2'
  AE 'build\prj\ph1p_pcie_integration_Runs\phy_1\ph1p_pcie_integration_phy.area' 'ec52ad2478593b580ec565c167353bc1755846bea627b58873ba893c89e58ccb' 75212 'P2'
  AE 'build\prj\ph1p_pcie_integration_Runs\phy_1\run.log' '3c9ebff1b03e90eb1a544b7334093d1190d8d84c44dc13595faa2357104efeec' 214347 'P2'
  AE 'build\prj\ph1p_pcie_integration_Runs\phy_1\route_flow.status' '2e7a138e3eba5b18a2df2b2d4dea32a8fca1e2fefe323ae3076b5fee6a6a1cd6' 1648 'P2'
  AE 'build\prj\ph1p_pcie_integration_Runs\phy_1\ph1p_pcie_integration_chk.timing' 'fbb135a5522d335622e67e0c895eb9b5ce5b2ea7fd6bd7b41490550172f7f686' 8682 'P2'
  AE 'build\dev-result.md' '6cf7ec1dbce4b5adf2ba5468a6a0333918ae6840b078d5393c5bfa0b19b7e18f' 6694 'P2'
  AE 'build\hardware-ready.md' '1dbb81364eaf232722a3fd1f703909ed4918adaa1eeaf56a433b424dbe4e3b84' 2900 'P2'
  AE 'sim-campaign\candidate-manifest.json' '01938ebb2eb6b56c18479877c64ad862f6dea5a724b2727f692bf4f710c2af72' 17323 'P3'
  AE 'sim-campaign\rtl-hash-check.txt' 'a8b46f3e512a07db5a5bdaa41939e4914276466643b075a9c46c55340c5be1b7' 1094 'P3'
  AE 'sim-campaign\freeze-verify.txt' 'f2a24f9c60efad90bb4a1a194e34d044d79dd1f81dca8238845bd02fc26435b2' 620 'P3'
  AE 'sim-campaign\campaign-summary.txt' '2d71f85ce8bc8dc37a50567c9a3c929fdc64c865113d037bb54c899bad27c1ee' 659 'P3'
  AE 'sim-campaign\dev-result.md' 'd6e562b9961b6355bfaad9ed7e1aee75fa375764bd699fd4c33f8c705d2aaabb' 3730 'P3'
  AE 'sim-campaign\dev-notes.md' '6ed5f9fbe9d85d273d0120b2077f4c8d1864b0bcc22df5490632c27cba829e74' 2398 'P3'
  AE 'sim-campaign\lessons.md' 'a6874da7084d88e41dbf2e733973ef9e73d98967e63bc085d8722d7556c189fb' 1201 'P3'
  AE 'sim-campaign\msim\tb_ddr_readback_campaign\vlog.log' '5bc861a49b24d357e1870b7088c2327c2e590c7af820cb7c34e8e317e127875e' 5280 'P3'
  AE 'sim-campaign\msim\tb_ddr_readback_campaign\vsim.log' '85bfa15b1275ddcd999e7536036530edf6f6bd92f661755b86c383769b6cdd2b' 1698 'P3'
  AE 'sim-campaign\msim\tb_ddr_readback_campaign\commands.log' '491c1404302cc7448c32c503f4d1b68b3da045fd3ef522630ad4ec05bf9e99ec' 647 'P3'
  AE 'sim-campaign\msim\tb_ddr_readback_campaign\vsim_stdout.log' 'e0e1e2621b04cf479e78a3cd24253729abd55025e64cae0d8b63d77765b05432' 3540 'P3'
  AE 'sim-campaign\msim\tb_ddr_readback_campaign\run.do' 'afe1f6c77d67457c87e0719767eb231a9da26e41cd653e29fee797fb6159cf39' 19 'P3'
  AE 'sim-campaign\msim\tb_ddr_readback_campaign\abs.f' '8b6964f88a0af88ae029b1455763a4009d8c9fe57475d0d44e8701fa1162709c' 2067 'P3'
  AE 'sim-campaign\msim\tb_ddr_readback_1080p\vlog.log' 'ba8306de7415bc3b0ec4d924248d579109a7feadc760bbde6fe6e2c5d024da05' 5154 'P3'
  AE 'sim-campaign\msim\tb_ddr_readback_1080p\vsim.log' 'f30f0f27c6d0de3d57f3cfb2da2649d9eb140117793de68aa8d5614d875ceb14' 947 'P3'
  AE 'sim-campaign\msim\tb_ddr_readback_1080p\commands.log' '6c0ff74795e54b611d2a0ca15302684382ba48d9a9440b7dcca9038c5cc73bd6' 638 'P3'
  AE 'sim-campaign\msim\tb_ddr_readback_1080p\vsim_stdout.log' '04ccdfa8f236f89d2bcbcac25b2ff44a8af76f8ff1c942844498205ff2a2aa54' 2038 'P3'
  AE 'sim-campaign\msim\tb_ddr_readback_1080p\run.do' 'afe1f6c77d67457c87e0719767eb231a9da26e41cd653e29fee797fb6159cf39' 19 'P3'
  AE 'sim-campaign\msim\tb_ddr_readback_1080p\abs.f' '6d47ab3794426524c68a1ff59938dd503e7897d30cc7987c18fb8a1e54030f5f' 2064 'P3'
  foreach($e in $ent){
    $total++
    $fp=Join-Path $run $e.p
    if(-not (Test-Path -LiteralPath $fp)){ $miss++; W ('MISSING|'+$e.grp+'|'+$e.p); continue }
    $h=(Get-FileHash -LiteralPath $fp -Algorithm SHA256).Hash.ToLower()
    $len=(Get-Item -LiteralPath $fp).Length
    if($e.exp.Length -eq 64){ $shaok=($h -eq $e.exp) } else { $shaok=$h.StartsWith($e.exp) }
    if($shaok -and ($len -eq $e.bytes)){ W ('MATCH|'+$e.grp+'|'+$e.p+'|'+$h+'|'+$len) }
    else { $script:mism++; W ('MISMATCH|'+$e.grp+'|'+$e.p+'|exp='+$e.exp+'|act='+$h+'|bytes_exp='+$e.bytes+'|bytes_act='+$len) }
  }
  $wl=@(
   @{p='rtl\ep_side\ddr\ddr_readback_int.v';sha='808a835c46a760a37749381c773defd920f02a3b65ef751e1b5d15b33d049ea7';blob='aff7f9fb234c8cbb29e19a50ec308233b67d32a9';b=10899},
   @{p='rtl\ep_side\ddr\ddr_frame_readback_checker.v';sha='5ca11a83c7a5cedcaa438e9bbd1e09c67a76394a20e02d47c00481e4307dc038';blob='ce220717431a187c6dc4b957a599b83ddeb75cf0';b=21473},
   @{p='rtl\ep_side\ph1p_pcie_ep_top.v';sha='77c692a12d6f8e251cd0f49672603a243f3766d07064f05f08f77f0f6a70b0ae';blob='92144a5f891d075d10696288918092e4580bdf5a';b=105647},
   @{p='rtl\ep_side\pcie_ep_engine.v';sha='b52924fab7cf3ddaf6c2786f9b5a5aa7b32387c32eccb3c57a91271385358f88';blob='d88212065fd23db80dc7781818b1d0c384483610';b=40387},
   @{p='rtl\ep_side\img\ep_bar_win.v';sha='2a25d6531849dfb4e9b61f01fbbd6d30e0e7dffcf8acb1aba3607864b186b62b';blob='03874377154756d2f5f634a46294f439b9cec71b';b=40254},
   @{p='sim\tb\tb_ddr_readback_int.v';sha='d173200d240a5d604da3846859404ce1a7d5b63eeac8e71dc3cec1db4d1e5772';blob='f000471e2cfedaa2e07f2eedb1fe1242a896e0f1';b=22224},
   @{p='sim\tb\tb_ep_bar_win_debug.v';sha='1fdbc8376830ddb95de8bbe11a4242c1e30905fd3a2507053550786b951d67e0';blob='58e11d4bc260b55debae1bc446f6eb9050799702';b=18797},
   @{p='sim\compile_checked.f';sha='558079c1451c870340201ee6767428f2a23b0dfc1d352176b08bf2ceda4ec69f';blob='35b12c518b58a683060e0618eb7d4970892bea90';b=2963},
   @{p='tools\pcie_integration\td\00_all_debug.tcl';sha='810241f7506b6f0352f51e4082cd6b8daa6e642402a9e8629769fc6138640707';blob='4c2fe6947614b30e4126bb6fbcfc55fce2080cc9';b=6259}
  )
  foreach($w in $wl){
    $total++
    $fp=Join-Path $wt $w.p
    if(-not (Test-Path -LiteralPath $fp)){ $miss++; W ('MISSING|WT|'+$w.p); continue }
    $h=(Get-FileHash -LiteralPath $fp -Algorithm SHA256).Hash.ToLower()
    $len=(Get-Item -LiteralPath $fp).Length
    $rel=$w.p -replace '\\','/'
    $bd=(""+(git -C $wt hash-object -- $rel 2>$null)).Trim().ToLower()
    $bn=(""+(git -C $wt hash-object --no-filters -- $rel 2>$null)).Trim().ToLower()
    $blobok=($bd -eq $w.blob) -or ($bn -eq $w.blob)
    if(($h -eq $w.sha) -and ($len -eq $w.b) -and $blobok){ W ('MATCH|WT|'+$w.p+'|sha='+$h+'|blob='+$bd+'|'+$len) }
    else { $script:mism++; W ('MISMATCH|WT|'+$w.p+'|exp_sha='+$w.sha+'|act_sha='+$h+'|exp_blob='+$w.blob+'|act_blob_def='+$bd+'|act_blob_nf='+$bn+'|exp_b='+$w.b+'|act_b='+$len) }
  }
  $tbl=@(
   @{p='sim\tb\tb_ddr_readback_campaign.v';sha='e1128cdef7368ef013c349171f179844de11dbea31fd21ade903f8e732569160';blob='0f1ab480b83733039f9333b1d16267abc3f9a912';b=17026},
   @{p='sim\tb\tb_ddr_readback_1080p.v';sha='f63c1d8ec7399fc62dbcf7d8f6713dc1e2019bbba97feefdaeba6e4d5e4cce69';blob='a75f5b4a39af3d54af4e73626541705c2bb9cfd7';b=10159}
  )
  foreach($w in $tbl){
    $total++
    $fp=Join-Path $wt $w.p
    if(-not (Test-Path -LiteralPath $fp)){ $miss++; W ('MISSING|P3TB|'+$w.p); continue }
    $h=(Get-FileHash -LiteralPath $fp -Algorithm SHA256).Hash.ToLower()
    $len=(Get-Item -LiteralPath $fp).Length
    $rel=$w.p -replace '\\','/'
    $bd=(""+(git -C $wt hash-object -- $rel 2>$null)).Trim().ToLower()
    $bn=(""+(git -C $wt hash-object --no-filters -- $rel 2>$null)).Trim().ToLower()
    if(($h -eq $w.sha) -and ($len -eq $w.b) -and (($bd -eq $w.blob) -or ($bn -eq $w.blob))){ W ('MATCH|P3TB|'+$w.p+'|sha='+$h+'|blob='+$bd+'|'+$len) }
    else { $script:mism++; W ('MISMATCH|P3TB|'+$w.p+'|exp_sha='+$w.sha+'|act_sha='+$h+'|exp_blob='+$w.blob+'|act_blob_def='+$bd+'|act_blob_nf='+$bn+'|exp_b='+$w.b+'|act_b='+$len) }
  }
  $pl=@(
   @{p='workflow\runs\20261018-1631_runA_fpga_side_readchannel\debug-fix3\prj\ph1p_pcie_integration_Runs\phy_1\ph1p_pcie_integration.bit';sha='bfafdf97ff78d6f6d2646ffc706542a0bbbb7e11869043ba754cf68a270813d0'},
   @{p='workflow\runs\20261018-1631_runA_fpga_side_readchannel\debug-fix3\prj\ph1p_pcie_integration_Runs\phy_1\cw\compiled.cwc';sha='8d2998b96ef1763c14a1302118235a687488297ce496692b1f6cd95d76981026'}
  )
  foreach($w in $pl){
    $total++
    $fp=Join-Path $root $w.p
    if(-not (Test-Path -LiteralPath $fp)){ $miss++; W ('MISSING|PROT|'+$w.p); continue }
    $h=(Get-FileHash -LiteralPath $fp -Algorithm SHA256).Hash.ToLower()
    if($h -eq $w.sha){ W ('MATCH|PROT|'+$w.p+'|'+$h) } else { $script:mism++; W ('MISMATCH|PROT|'+$w.p+'|exp='+$w.sha+'|act='+$h) }
  }
  $rep=Get-ChildItem -LiteralPath (Join-Path $run 'test-reports') -File | Sort-Object Name
  foreach($f in $rep){
    $h=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLower()
    W ('REPORT|'+$f.Name+'|'+$h+'|'+$f.Length)
  }
  $head=(git -C $wt rev-parse HEAD).Trim()
  $st=@(git -C $wt status --porcelain)
  $mcount=@($st | Where-Object { $_ -match '^ M ' }).Count
  $ucount=@($st | Where-Object { $_ -match '^\?\? ' }).Count
  W ('WT_HEAD='+$head)
  W ('WT_STATUS_M='+$mcount+'|WT_STATUS_UNTRACKED='+$ucount)
  $diff=Join-Path $run 'checker-integrate\candidate.diff'
  git -C $wt apply --check --cached --whitespace=nowarn $diff 2>$null | Out-Null; $rc1=$LASTEXITCODE
  git -C $wt apply --check --reverse --whitespace=nowarn $diff 2>$null | Out-Null; $rc2=$LASTEXITCODE
  $db=[IO.File]::ReadAllBytes($diff)
  $nul=@($db | Where-Object { $_ -eq 0 }).Count
  $txt=[Text.Encoding]::UTF8.GetString($db)
  $bad=([regex]::Matches($txt,[string][char]0xFFFD)).Count
  $nDiff=([regex]::Matches($txt,'(?m)^diff --git ')).Count
  $nNew=([regex]::Matches($txt,'(?m)^new file mode ')).Count
  W ('DIFF_APPLY_HEAD_TO_INDEX_RC='+$rc1+'|DIFF_REVERSE_TO_WT_RC='+$rc2+'|DIFF_HEADS='+$nDiff+'|NEW_FILES='+$nNew+'|NUL='+$nul+'|UTFFFD='+$bad)
  $bit=Join-Path $run 'build\prj\ph1p_pcie_integration_Runs\phy_1\ph1p_pcie_integration.bit'
  $cwc=Join-Path $run 'build\prj\ph1p_pcie_integration_Runs\phy_1\cw\compiled.cwc'
  $dstBit=Join-Path $stage 'compiled.bit'
  $dstCwc=Join-Path $stage 'compiled.cwc'
  if((Test-Path -LiteralPath $dstBit) -or (Test-Path -LiteralPath $dstCwc)){ W 'STAGE_COLLISION_NO_COPY'; P 'STAGE_COLLISION_NO_COPY' }
  else { Copy-Item -LiteralPath $bit -Destination $dstBit; Copy-Item -LiteralPath $cwc -Destination $dstCwc }
  $shBit=(Get-FileHash -LiteralPath $dstBit -Algorithm SHA256).Hash.ToLower()
  $shCwc=(Get-FileHash -LiteralPath $dstCwc -Algorithm SHA256).Hash.ToLower()
  W ('STAGE_BIT_SHA='+$shBit+'|MATCH='+($shBit -eq '5b67a8f5925327ba9d0442d9e4228fcfd254c80a2f86d921ceda70ecae111d52'))
  W ('STAGE_CWC_SHA='+$shCwc+'|MATCH='+($shCwc -eq '8dda54d4efa8e6be728a6ebb34686f25de90a36b039eda6f831dfb9c346c664f'))
  $bwcmd=@('connect_cable -host_name 127.0.0.1:5555 -usr_args  -open','read_device_id',('download -bit '+$dstBit+' -mode jtag -spd 7 -cable 0'),'read_device_id','connect_cable -close')
  [IO.File]::WriteAllLines((Join-Path $stage 'preload.bwcmd'),$bwcmd,(New-Object Text.UTF8Encoding($false)))
  $shr=@(('created_at='+(Get-Date -Format 'yyyy-MM-ddTHH:mm:sszzz')),('source_bit='+$bit),('source_cwc='+$cwc),('bit_sha256='+$shBit),('cwc_sha256='+$shCwc),'mode=SRAM only (-mode jtag); no flash/efuse/SPI/svf; max 1 download; no retry on failure','preload.bwcmd = staged command script; executed only if user confirms board window free')
  [IO.File]::WriteAllLines((Join-Path $stage 'staging-record.txt'),$shr,(New-Object Text.UTF8Encoding($false)))
  W ('STAGE_DIR='+$stage)
  $now=@(Get-Process td,hwserver -ErrorAction SilentlyContinue | ForEach-Object { $_.Id.ToString()+':'+$_.ProcessName })
  W ('PROCS_NOW='+($now -join ','))
} catch {
  W ('EXCEPTION='+$_.Exception.Message)
} finally {
  [IO.File]::WriteAllLines($logFile,$log,(New-Object Text.UTF8Encoding($false)))
}
P ('SUMMARY total='+$total+' mismatch='+$mism+' missing='+$miss)
P ('STAGE='+$stage)
P ('LOG='+$logFile)
$log | Where-Object { $_ -match 'MISMATCH|MISSING|REPORT|DIFF_|WT_HEAD|STAGE_|EXCEPTION' } | ForEach-Object { P $_ }
