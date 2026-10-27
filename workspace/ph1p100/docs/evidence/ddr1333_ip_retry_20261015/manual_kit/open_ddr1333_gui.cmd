@echo off
cd /d "%~dp0"
"D:/downlaod/bin/IpTool.exe" "D:/downlaod" "-user" "D:/TD/work/csi2/_validation/ddr1333_ip_20261015_190248/source/ddrmc_x32/ddrmc_x32.xml" "-gen" "D:/TD/work/csi2/_validation/ddr1333_ip_20261015_190248/depot/Component.xml" "-device" "PH1P100SBG484" "-export_to" "D:/TD/work/csi2/_validation/ddr1333_ip_20261015_190248/output" "-comp" "ddrmc_1333"
echo IPTool window closed. Keep this folder for review.
pause
