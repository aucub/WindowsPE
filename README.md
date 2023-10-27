# Windows PE


Build &amp; customization of WinPE


- [Windows PE](#windows-pe)
  - [Basic](#basic)
  - [Customization](#customization)
    - [Basic commands](#basic-commands)
    - [Drivers](#drivers)
    - [Applications](#applications)
    - [Files](#files)
    - [Enabled components](#enabled-components)
      - [Inactive Components](#inactive-components)
  - [Documentation](#documentation)

## Basic

- New-WinPE
- New-FolderStructure
  - _change bloated structure to MDT-based structure_
    -  Remove root language folders and sources
    -  Add MDT-structure and move `boot.wim` to `Deploy\Boot`
- Mount-WinPE
- Add-FilesToWinPE
  - _Loop over contents `source\_winpe`_
- Add-AppsToWinPE
  - _Download applications (portable) and installs to target path_
- Add-OptionalComponents
- Add-BootDrivers
  - _none, all, hp, dell, lenovo, vmware_
  - _Release will contain 'all'_
- Add-Updates
  - `Disabled`
- Invoke-WinPEcleanup
  -  `Disabled`
- Get-HashOfContents
  -  `Disabled` due to permsssion issue in boot.wim system files
- Dismount-Image
- Add-FilesToIso
  - _Loop over contents `source\_iso`_
- Set-BCDData
  - _Required due to folder structure change_
- New-ISO

_Screenshot after <15sec boot:_

![image](https://user-images.githubusercontent.com/12066560/165970164-51bd4f18-9192-4082-a866-2cdbacbd5caa.png)

## Customization
### Basic commands
- Mount <br>`Mount-WindowsImage -ImagePath "$ISO_root\Deploy\Boot\boot.wim" -index 1  -Path "$WinPE_root"`
- Unmount <br> `Dismount-WindowsImage -Path "$WinPE_root" -Save`
- ToISO <br> `makeWinPEMedia.cmd /ISO $workingDirectory\WinPE_$arch workingDirectory\WinPE_$arch.iso`

### Drivers
- `Add-WindowsDriver -Path "$WinPE_root" -Driver ".\source\Drivers\$branding" -verbose -Recurse"`

### Applications

- Launchbar 
  - Quicklaunch for apps
- DeploymentMonitoringTool.exe (included in source)
  - Get info about current machine
- CMTrace_amd64.exe (included in source)
  - Read MDT and other logs
- Process Explorer
- 7-Zip
- Powershell 7+
- Notepad++
- DoubleCMD
  - File Explorer as Explorer.exe is unavailable 
- Dism++
- DiskGenius
- WinNTSetup
- BOOTICE
- CGI-plus
- UltraISO
- PECMD
- Missing executables and added:
  - label
  - logman
  - runas
  - sort
  - tzutil
  - Utilman
  - clip
  - eventcreate
  - forfiles
  - setx
  - timeout
  - waitfor
  - where
  - whoami.exe

### Files
- WinPE (X:\)
  - Add to `$workingDirectory\WinPE_$arch\mount` folder.
  - Included files in `source\_winpe\Windows\System32` to be added to `$workingDirectory\WinPE_$arch\mount\Windows\System32`
    - CMTrace_amd64.exe
    - DeploymentMonitoringTool.exe
    - BOOTICE.exe
    - launchbar.ini
    - winpeshl.ini 
- ISO
  - Add to `"$workingDirectory\WinPE_$arch\media"` folder


### Enabled components
<details>
  <summary>Click to show</summary>
    
- WinPE-HTA
- WinPE-WMI
- WinPE-NetFX
- WinPE-Scripting
- WinPE-SecureStartup
- WinPE-PlatformID
- WinPE-PowerShell
- WinPE-DismCmdlets
- WinPE-SecureBootCmdlets
- WinPE-StorageWMI
- WinPE-EnhancedStorage
- WinPE-Dot3Svc
- WinPE-FMAPI
- WinPE-FontSupport-WinRE
- WinPE-WDS-Tools
- WinPE-WinReCfg
- WinPE-Font Support-ZH-CN
</details>
    
#### Inactive Components
<details>
  <summary>Click to show</summary>
    
- WinPE-Fonts-Legacy
- WinPE-Font Support-JA-JP
- WinPE-Font Support-KO-KR
- WinPE-Font Support-ZH-HK
- WinPE-GamingPeripherals
- WinPE-MDAC
- WinPE-PPPoE
- WinPE-Rejuv
- WinPE-RNDIS
- WinPE-SRT
- WinPE-WiFi-Package
- Winpe-LegacySetup
- WinPE-Setup
- WinPE-Setup-Client
- WinPE-Setup-Server
</details>


## Documentation

- [WinPE Optional Components](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/winpe-add-packages--optional-components-reference?view=windows-11)
