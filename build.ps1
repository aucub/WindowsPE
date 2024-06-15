# 设置变量
Param(
    [ValidateSet("all", "none", "hp", "dell", "lenovo")]$branding = "all", 
    [boolean]$mdt = $false, # Microsoft 部署工具包
    [ValidateSet("amd64", "x86", "arm", "arm64")]$arch = "amd64",
    [string]$workingDirectory = $env:GITHUB_WORKSPACE
)

$json = get-content -path .\env.json -raw | convertfrom-json

$old_loc = $PWD

if ($arch -eq "amd64") { $arch_short = "x64" } else { $arch_short = $arch } #amd64 to x64
set-variable -name adkPATH      -value  "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit" -verbose
set-variable -name WinPEPATH    -value  "$adkPATH\Windows Preinstallation Environment" -verbose 
set-variable -name DeployImagingToolsENV -value "$adkPATH\Deployment Tools\DandISetEnv.bat" -verbose
set-variable -name WinPE_root   -value  "$workingDirectory\WinPE_$arch\mount" -verbose 
set-variable -name ISO_root     -value  "$workingDirectory\WinPE_$arch\media" -verbose

# 检查目录是否存在，如果不存在，则创建它
if (!(test-path -path $workingDirectory)) { new-item -itemtype directory -path $workingDirectory }   
if (!(test-path -path .\source\_iso)) { New-Item -ItemType Directory -Path .\source -Name _iso -force -verbose }
if (!(test-path -path $workingDirectory\source)) { copy-item -Path .\source -destination $workingDirectory -recurse }
set-location $workingDirectory

# 新建目录
New-Item -ItemType Directory -Path $workingDirectory -Name temp -force -verbose 
New-Item -ItemType Directory -Path $workingDirectory -Name source\Drivers\$branding -force  -verbose 

<#
.SYNOPSIS
创建 WinPE 环境

.NOTES
- fwfiles: efisys.bin,etfsboot.com
- media: sources, bootmgr,bootmgr.efi, EFI, BOOT
- mount: empty
#>
function New-WinPE() {
    "Start the Deployment and Imaging Tools Environment & Create WinPE for $arch" | write-host -foregroundcolor magenta
    cmd /c """$DeployImagingToolsENV"" && copype.cmd $arch ""$workingDirectory\WinPE_$arch"" && exit"
    # 检查 WinPE 文件夹是否创建成功
    if (!(test-path -path "$workingDirectory\WinPE_$arch") -or ($LASTEXITCODE -eq 1)) {
        "unable to create $workingDirectory\WinPE_$arch" | write-host -foregroundcolor cyan
        set-location $old_loc
        exit 1
    }
    # 删除 efisys.bin 文件以修复按任意键从 DVD 启动的问题
    remove-item -path "$workingDirectory\WinPE_$arch\fwfiles\efisys.bin"
    # 复制新的 efisys.bin 文件
    copy-item -path "$adkPATH\Deployment Tools\amd64\Oscdimg\efisys_noprompt.bin" -Destination "$workingDirectory\WinPE_$arch\fwfiles\efisys.bin"
    # 获取 boot.wim 文件的原始大小
    $global:orisize = get-item -path "$ISO_root\sources\boot.wim" | Select-Object -ExpandProperty length
}

function New-FolderStructure() {
    <#
.SYNOPSIS
生成文件夹结构

.NOTES
    Boot
    Deploy\Boot\{boot.wim -> LiteTouchPE_x64.wim} 
    EFI
    bootmgr
    bootmgr.efi    
#>
    # 清理路径下的文件和文件夹
    get-childitem -Path $ISO_root\* -exclude @("bootmgr", "bootmgr.efi", "sources", "Boot", "EFI") -Depth 0 | remove-item -recurse
    # 生成文件夹结构
    foreach ($f in @("Tools", "Templates", "Servicing", "Scripts", "Packages", "Out-of-Box Drivers", "Operating Systems", "Control", "Captures", "Boot", "Backup", "Applications", "`$OEM`$")) {
        New-Item -ItemType Directory -path  "$ISO_root\Deploy" -name "$f"
    }
    # 移动 boot.wim 文件到目标文件夹
    move-item -path "$ISO_root\sources\boot.wim" "$ISO_root\Deploy\Boot\"
    # 删除 sources 文件夹
    remove-item -path "$ISO_root\sources" -force 
}

function Mount-WinPE() {
    <#
.SYNOPSIS
挂载 boot.wim 到 WinPE_$arch\mount

.NOTES
General notes
#>
    "Mounting boot.wim image" | write-host -foregroundcolor magenta
    Mount-WindowsImage -ImagePath "$ISO_root\Deploy\Boot\boot.wim" -index 1  -Path "$WinPE_root"
    cmd /c "Dism /Set-ScratchSpace:512 /Image:""$WinPE_root"""

}

Function Add-OptionalComponents() {
    <#
.SYNOPSIS
添加 WinPE 可选组件

.NOTES
General notes
#>

    "Adding Optional Components to boot.wim" | write-host -foregroundcolor magenta
    # 遍历组件
    foreach ($c in $json.WinPEOptionalComponents) {
        "Adding: $c" | write-host -foregroundcolor cyan

        # 添加组件
        Add-WindowsPackage -Path "$WinPE_root" -PackagePath "$WinPEPATH\$arch\WinPE_OCs\$c.cab" -PreventPending
        # 添加语言包
        if (test-path -path "$WinPEPATH\$arch\WinPE_OCs\zh-cn\$c`_zh-cn.cab" ) {
            Add-WindowsPackage -Path "$WinPE_root" -PackagePath "$WinPEPATH\$arch\WinPE_OCs\zh-cn\$c`_zh-cn.cab" -PreventPending
        }
        else {
            "$c`_zh-cn.cab not found.. continuing" | write-host -foregroundcolor cyan
        }
    }
}

function Add-FilesToWinPE() {
    <#
.SYNOPSIS
从.\source\_winpe添加文件到 WinPE (Boot.wim)

.NOTES
文件名需要不包含 .ignore
#>
    "Adding Files & Folders to WinPE" | write-host -ForegroundColor magenta
    
    $folders = get-childitem -directory -Path ".\source\_winpe" -Recurse |  Where-Object { $_.FullName -notlike "*.ignore*" }  | select -ExpandProperty fullname
    $files = get-childitem -file -Path ".\source\_winpe" -Recurse |  Where-Object { $_.FullName -notlike "*.ignore*" }  | select -ExpandProperty fullname
    
    # 文件夹
    foreach ($fo in $folders) {
        # 获取相对路径
        $shortpath = $fo.Substring("$workingdirectory\source\_winpe".length + 1, $fo.length - "$workingdirectory\source\_winpe".length - 1)
        if (!(test-path -path "$WinPE_root\$shortpath")) {
            New-Item -ItemType Directory "$WinPE_root\$shortpath" -verbose
        }
    }

    # 文件
    foreach ($fi in $files) {
        $shortpath = $fi.Substring("$workingdirectory\source\_winpe".length + 1, $fi.length - "$workingdirectory\source\_winpe".length - 1)
        copy-item -path  "$fi" -destination "$WinPE_root\$shortpath" -verbose
    }

}

function Add-AppsToWinPE() {
    <#
.SYNOPSIS

.NOTES
General notes
#>
    # 下载应用
    #process explorer
    invoke-restmethod -OutFile ".\temp\ProcessExplorer.zip" -uri "https://download.sysinternals.com/files/ProcessExplorer.zip"
    7z t ".\temp\ProcessExplorer.zip"
    if ($LASTEXITCODE -eq 0) {
        7z x -y ".\temp\ProcessExplorer.zip" -o".\temp" 
        copy-item -path ".\temp\procexp64.exe" -Destination "$WinPE_root\windows\system32\" -verbose
    }
	
    # 7zip
    invoke-restmethod -OutFile ".\temp\7z.exe" -uri "https://www.7-zip.org/a/7z2406-x64.exe"
    7z t ".\temp\7z.exe"
    if ($LASTEXITCODE -eq 0) {
        7z x -y ".\temp\7z.exe" -o"$WinPE_root\Program Files\7-Zip" 
    }

    # Powershell 7
    invoke-restmethod -OutFile ".\temp\pwsh.ps1"  -Uri 'https://aka.ms/install-powershell.ps1'
    .\temp\pwsh.ps1  -Destination "$WinPE_root\Program Files\PowerShell\7"

    # notepad ++
    invoke-restmethod -OutFile ".\temp\npp.zip" -uri "https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.6.8/npp.8.6.8.portable.x64.zip"
    7z t ".\temp\npp.zip"
    if ($LASTEXITCODE -eq 0) {
        7z x -y ".\temp\npp.zip" -o"$WinPE_root\Program Files\Notepad++" 
    }

    # launchbar
    Invoke-RestMethod -OutFile ".\temp\LaunchBar.exe" -Uri "https://www.lerup.com/php/download.php?LaunchBar/LaunchBar_x64.exe"
    copy-item ".\temp\LaunchBar.exe" -Destination "$WinPE_root\windows\system32\" -verbose

    # doublecmd
    Invoke-RestMethod -OutFile ".\temp\doublecmd.zip" -uri "https://github.com/doublecmd/doublecmd/releases/download/v1.1.15/doublecmd-1.1.15.x86_64-win64.zip"
    7z t ".\temp\doublecmd.zip"
    if ($LASTEXITCODE -eq 0) {
        7z x -y ".\temp\doublecmd.zip" -o"$WinPE_root\Program Files" 
    }    

    # Dism++
    Invoke-RestMethod -OutFile ".\temp\Dism++.zip" -uri "https://github.com/Chuyu-Team/Dism-Multi-language/releases/download/v10.1.1002.2/Dism++10.1.1002.1B.zip"
    7z t ".\temp\Dism++.zip"
    if ($LASTEXITCODE -eq 0) {
        7z x -y ".\temp\Dism++.zip" -o"$WinPE_root\Program Files\Dism++" 
    }  

    # DiskGenius
    7z t ".\source\DiskGenius.zip"
    if ($LASTEXITCODE -eq 0) {
        7z x -y ".\source\DiskGenius.zip" -o"$WinPE_root\Program Files" 
    }

    # cpu-z
    Invoke-RestMethod -OutFile ".\temp\cpu-z.zip" -uri "https://download.cpuid.com/cpu-z/cpu-z_2.09-cn.zip"
    7z t ".\temp\cpu-z.zip"
    if ($LASTEXITCODE -eq 0) {
        7z x -y ".\temp\cpu-z.zip" -o"$WinPE_root\Program Files\cpu-z" 
    }  

    # imgdrive
    Invoke-RestMethod -OutFile ".\temp\imgdrive.zip" -uri "https://download.yubsoft.com/imgdrive_2.1.8_portable.zip"
    7z t ".\temp\imgdrive.zip"
    if ($LASTEXITCODE -eq 0) {
        7z x -y ".\temp\imgdrive.zip" -o"$WinPE_root\Program Files\imgdrive" 
    }

    # CGI-plus
    7z t ".\source\CGI-plus.zip"
    if ($LASTEXITCODE -eq 0) {
        7z x -y ".\source\CGI-plus.zip" -o"$WinPE_root\Program Files\CGI-plus" 
    }

    # PECMD
    7z t ".\source\PECMD.zip"
    if ($LASTEXITCODE -eq 0) {
        7z x -y ".\source\PECMD.zip" -o"$WinPE_root\Program Files" 
    }

    # 中文
    Add-WindowsPackage -Path "$WinPE_root" -PackagePath "$WinPEPATH\$arch\WinPE_OCs\zh-cn\lp.cab" -PreventPending
    Dism /Set-AllIntl:zh-CN /Image:"$WinPE_root"
    Dism /Set-TimeZone:"China Standard Time" /Image:"$WinPE_root"

    # 工具
    $json = @"
{
    "System32": [
        "System32\\label.exe",
        "System32\\logman.exe",
        "System32\\runas.exe",
        "System32\\sort.exe",
        "System32\\tzutil.exe",
        "System32\\Utilman.exe",
        "System32\\clip.exe",
        "System32\\eventcreate.exe",
        "System32\\forfiles.exe",
        "System32\\setx.exe",
        "System32\\timeout.exe",
        "System32\\waitfor.exe",
        "System32\\where.exe",
        "System32\\whoami.exe"
        ]
    }
"@ | convertfrom-json
    foreach ($j in $json.system32) {
        Copy-Item -path "$env:SystemRoot\$j" -Destination "$WinPE_root\windows\system32\" -verbose
    }
}

function Add-BootDrivers() {
    <#
.SYNOPSIS
添加 OEM 的启动关键驱动程序

.NOTES
网络、磁盘、芯片组
#>
    # 获得驱动列表
    $arr = if ($branding -eq "all") {
        $json.bootdrivers.PSOBJect.Properties.value
    }
    elseif ($branding -eq "none") {
        $null
    }
    else {
        $json.bootdrivers.$branding
    }
    "Adding drivers" | write-host -ForegroundColor magenta
    # 遍历驱动列表复制文件
    foreach ($b in $arr) {
        "$b" | write-host -ForegroundColor cyan

        if ((test-path($b)) -and ($b -notlike ".\source\Drivers\$branding")) {
            # 复制文件
            Copy-Item -Path "$b" -Destination ".\source\Drivers\$branding" -Verbose
        }
        elseif ($b -match 'https?://.*?\.(zip|rar|exe|7z|cab)') {
            # 下载文件
            $filename = $b | split-path -Leaf
            $foldername = $filename | Split-Path -LeafBase
            $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
            $session.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.127 Safari/537.36"
            Invoke-WebRequest -UseBasicParsing -Uri "$b" -WebSession $session -OutFile .\temp\$filename
            # 解压存档
            7z t ".\temp\$filename"
            if ($LASTEXITCODE -eq 0) {
                7z x -y ".\temp\$filename" -o".\source\Drivers\$branding\$foldername" 
            }
            else {
                "unable to extract $b " | write-host -ForegroundColor cyan
                continue
            }
        }
        else {
            "$b is not a file or an URL" | write-host -ForegroundColor cyan
            continue
        }
    }

    "Injecting drivers from .\source\Drivers" | write-host -ForegroundColor cyan
    # 添加驱动
    Add-WindowsDriver -Path "$WinPE_root" -Driver ".\source\Drivers\$branding" -verbose -Recurse
}


function Add-Updates() {
    <#
    .SYNOPSIS
    添加更新
    
    .NOTES
    
    #>
    Write-Host "Injecting updates from .\source\Updates"
    Get-ChildItem ".\source\Updates" | ForEach-Object { 
        Add-WindowsPackage -Path $WinPE_root -PackagePath ".\source\Updates\$_" 
    }
}


Function Dismount-Image() {
    <#
.SYNOPSIS
卸载 boot.wim

.NOTES
General notes
#>

    "Unmounting boot.wim image" | write-host -foregroundcolor magenta
    Dismount-WindowsImage -Path "$WinPE_root" -Save
    $endsize = get-item -path "$ISO_root\Deploy\Boot\boot.wim" | Select-Object -ExpandProperty length
    "Size increase after modifying: $([float]($endsize / $global:orisize)) - $global:orisize-->$endsize" | write-host -foregroundcolor magenta
}

Function Add-FilesToIso() {
    <#
.SYNOPSIS
将其他文件添加到 iso 文件

.NOTES
General notes
#>
    "Adding Contents of source\_iso to ISO" | write-host -ForegroundColor magenta
    copy-item -Path ".\source\_iso\*" -destination "$ISO_root" -recurse -verbose
}

Function Set-BCDData() {
    <#
.SYNOPSIS
设置 BCD

.NOTES
General notes
#>

    "update *.wim in BCD" | write-host -foregroundcolor magenta
    # 找到 wim 并获取路径
    $wimPath = get-childitem -path $ISO_root\*.wim -Recurse | Select-Object -ExpandProperty FullName 
    $filePath = $wimpath.substring($ISO_root.length, ($wimpath.length - $ISO_root.length) )
    "filepath: $filePath" | write-host -ForegroundColor Cyan
    $bcdPath1 = "$ISO_root\Boot\BCD"
    $enumcommand1 = "bcdedit /store $bcdPath1"
    $rawbcdstring1 = invoke-expression $enumcommand1 | select-string -pattern "^device\s*(?<device>.*)$"
    $bcdstring1 = $rawbcdstring1.Matches.Groups.where({ $_.Name -eq "device" }).Value
    $bcdstring1 = $bcdstring1.Replace("\sources\boot.wim", $filePath)
    $commands1 = @("device", "osdevice") | foreach-object { "bcdedit --% /store `"$bcdpath1`" /set `{default`} $_ $bcdstring1" }
    $commands1 | foreach-object { invoke-expression $_ }

    # EFI
    $bcdPath2 = "$ISO_root\EFI\Microsoft\Boot\BCD" 
    $enumcommand2 = "bcdedit /store $bcdPath2"
    $rawbcdstring2 = invoke-expression $enumcommand2 | select-string -pattern '^device\s*(?<device>.*)$'
    $bcdstring2 = $rawbcdstring2.Matches.Groups.where({ $_.Name -eq "device" }).Value
    $bcdstring2 = $bcdstring2.Replace("\sources\boot.wim", $filePath)
    $commands2 = @("device", "osdevice") | foreach-object { "bcdedit --% /store `"$bcdpath2`" /set `{default`} $_ $bcdstring2" }
    $commands2 | foreach-object { invoke-expression $_ }
}

Function New-ISO() {
    <#
.SYNOPSIS
从 .\WinPE_$arch 创建 .iso 文件

.NOTES
General notes
#>

    "Start the Deployment and Imaging Tools Environment & Create ISO file from WinPE_$arch folder" | write-host -foregroundcolor magenta
    cmd /k """$DeployImagingToolsENV"" && makeWinPEMedia.cmd /ISO ""$workingDirectory\WinPE_$arch"" ""$workingDirectory\WinPE_$arch.iso"" && exit"
}

# 创建WinPE
New-WinPE
New-FolderStructure
Mount-WinPE
Add-FilesToWinPE
Add-AppsToWinPE
Add-OptionalComponents
Add-BootDrivers
#Add-Updates
Dismount-Image
Add-FilesToIso
Set-BCDData
New-ISO

set-location $old_loc