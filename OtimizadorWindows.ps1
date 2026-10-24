<#
.SYNOPSIS
    Otimizador de Performance para Windows 10/11 - menu interativo.
.DESCRIPTION
    - Verifica privilégios de administrador (e pede elevação automaticamente).
    - Cria ponto de restauração (opcional) e guarda o valor ORIGINAL de cada
      alteração (registro, serviços e tarefas) para reversão pela opção [R].
    - Usa apenas ajustes documentados e reversíveis. Não inclui "mitos" de
      otimização (ex.: limpar RAM por script, reserva de banda QoS de 20%, etc.).
    - Registo de atividade em %ProgramData%\OtimizadorWindows\otimizador.log
.NOTES
    Teste primeiro numa máquina não crítica e valide com a sua equipa de T.I.
#>

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Script:Versao      = '1.0'
$Script:Pasta       = Join-Path $env:ProgramData 'OtimizadorWindows'
$Script:LogFile     = Join-Path $Script:Pasta 'otimizador.log'
$Script:BackupFile  = Join-Path $Script:Pasta 'backup.jsonl'
$Script:Reiniciar   = $false
$Script:Largura     = 72

# ───────────────────────── Verificação de privilégios ─────────────────────────
function Test-Admin {
    $p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "`n  [!] Este programa precisa de privilégios de Administrador." -ForegroundColor Yellow
    Write-Host "      A solicitar elevação (UAC)..." -ForegroundColor Gray
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } catch {
        Write-Host "  [X] Elevação recusada. Execute como Administrador." -ForegroundColor Red
        Start-Sleep -Seconds 4
    }
    exit
}

$Script:Build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
if ($Script:Build -lt 10240) {
    Write-Host "  [X] Requer Windows 10 ou superior." -ForegroundColor Red; Start-Sleep 4; exit
}
$Script:EhWin11 = $Script:Build -ge 22000
if (-not (Test-Path $Script:Pasta)) { New-Item -ItemType Directory -Path $Script:Pasta -Force | Out-Null }
$Host.UI.RawUI.WindowTitle = "Otimizador de Performance v$Script:Versao (Administrador)"

# ───────────────────────────── Funções de interface ─────────────────────────────
function Write-Log($Nivel, $Msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Nivel] $Msg" | Add-Content -Path $Script:LogFile -Encoding UTF8
}
function Write-OK($m)   { Write-Host "  [✔] $m" -ForegroundColor Green;  Write-Log 'OK'   $m }
function Write-Info($m) { Write-Host "  [i] $m" -ForegroundColor Cyan;   Write-Log 'INFO' $m }
function Write-Warn($m) { Write-Host "  [!] $m" -ForegroundColor Yellow; Write-Log 'AVISO' $m }
function Write-Err($m)  { Write-Host "  [✘] $m" -ForegroundColor Red;    Write-Log 'ERRO' $m }

function Center([string]$t, [int]$w) {
    $p = [math]::Max(0, $w - $t.Length); $e = [int][math]::Floor($p / 2)
    (' ' * $e) + $t + (' ' * ($p - $e))
}

function Show-Header([string]$Subtitulo = '') {
    Clear-Host
    $l = '═' * $Script:Largura
    Write-Host "╔${l}╗" -ForegroundColor Cyan
    Write-Host ("║{0}║" -f (Center 'OTIMIZADOR DE PERFORMANCE  •  WINDOWS 10 / 11' $Script:Largura)) -ForegroundColor White
    Write-Host ("║{0}║" -f (Center "Versão $Script:Versao  |  Modo Administrador" $Script:Largura)) -ForegroundColor DarkCyan
    Write-Host "╚${l}╝" -ForegroundColor Cyan
    if ($Subtitulo) {
        Write-Host "`n  ▌ $Subtitulo" -ForegroundColor Yellow
        Write-Host ("  " + ('─' * ($Script:Largura - 2))) -ForegroundColor DarkGray
    }
}

function Pausar { Write-Host ""; Read-Host "  Pressione ENTER para continuar" | Out-Null }

function Confirm-Acao([string]$Msg) {
    (Read-Host "  $Msg [S/N]") -match '^[sSyY]'
}

function Invoke-Step([string]$Descricao, [scriptblock]$Acao) {
    try { & $Acao; Write-OK $Descricao }
    catch { Write-Err "$Descricao -> $($_.Exception.Message)" }
}

function Invoke-Menu([string]$Titulo, [array]$Itens) {
    while ($true) {
        Show-Header $Titulo
        for ($i = 0; $i -lt $Itens.Count; $i++) {
            Write-Host ("   [{0,2}] {1}" -f ($i + 1), $Itens[$i].N)
        }
        Write-Host "   [ 0] Voltar ao menu principal" -ForegroundColor DarkGray
        $e = Read-Host "`n  Escolha"
        if ($e -eq '0') { return }
        if ($e -match '^\d+$' -and [int]$e -ge 1 -and [int]$e -le $Itens.Count) {
            Write-Host ""
            try { & $Itens[[int]$e - 1].A } catch { Write-Err $_.Exception.Message }
            Pausar
        }
    }
}

# ──────────────────────── Backup / restauro de alterações ────────────────────────
function Save-Backup([hashtable]$Obj) {
    ($Obj | ConvertTo-Json -Compress) | Add-Content -Path $Script:BackupFile -Encoding UTF8
}

function Set-Reg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    $existed = $false; $old = $null; $kind = $Type
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    else {
        $k = Get-Item -LiteralPath $Path
        if ($k.GetValueNames() -contains $Name) {
            $existed = $true
            $old  = $k.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
            $kind = [string]$k.GetValueKind($Name)
        }
    }
    Save-Backup @{ Tipo = 'reg'; Path = $Path; Name = $Name; Existed = $existed; Old = $old; Kind = $kind }
    Set-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -Type $Type -Force
}

function Set-Svc([string]$Name, [string]$Modo) {   # Modo: Disabled | Manual | Auto
    $s = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
    if (-not $s) { return $false }
    if ($s.StartMode -notin 'Auto', 'Manual', 'Disabled') { return $false }
    Save-Backup @{ Tipo = 'svc'; Name = $Name; Old = $s.StartMode }
    if ($Modo -eq 'Disabled') { Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue }
    $m = @{ Disabled = 'disabled'; Manual = 'demand'; Auto = 'auto' }[$Modo]
    & sc.exe config $Name start= $m | Out-Null
    return $true
}

function Disable-Tarefa([string]$Path, [string]$Name) {
    $t = Get-ScheduledTask -TaskPath $Path -TaskName $Name -ErrorAction SilentlyContinue
    if (-not $t -or $t.State -eq 'Disabled') { return }
    Save-Backup @{ Tipo = 'task'; Path = $Path; Name = $Name }
    Disable-ScheduledTask -TaskPath $Path -TaskName $Name | Out-Null
}

function Restore-All {
    if (-not (Test-Path $Script:BackupFile)) { Write-Info "Nenhuma alteração registada para reverter."; return }
    if (-not (Confirm-Acao "Reverter TODAS as alterações feitas por este programa?")) { return }
    $seen = @{}
    $itens = Get-Content $Script:BackupFile -Encoding UTF8 | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json }
    foreach ($i in $itens) {                      # o 1.º registo de cada item é o valor original
        $chave = "$($i.Tipo)|$($i.Path)|$($i.Name)"
        if ($seen[$chave]) { continue }; $seen[$chave] = $true
        try {
            switch ($i.Tipo) {
                'reg' {
                    if ($i.Existed) { Set-ItemProperty -LiteralPath $i.Path -Name $i.Name -Value $i.Old -Type $i.Kind -Force }
                    else { Remove-ItemProperty -LiteralPath $i.Path -Name $i.Name -ErrorAction SilentlyContinue }
                }
                'svc'  { $m = @{ Disabled = 'disabled'; Manual = 'demand'; Auto = 'auto' }[$i.Old]; & sc.exe config $i.Name start= $m | Out-Null }
                'task' { Enable-ScheduledTask -TaskPath $i.Path -TaskName $i.Name | Out-Null }
            }
            Write-OK "Revertido: $($i.Tipo) $($i.Name)"
        } catch { Write-Err "Falha ao reverter $($i.Name): $($_.Exception.Message)" }
    }
    Remove-Item $Script:BackupFile -Force
    $Script:Reiniciar = $true
}

function New-Restore {
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "Otimizador Windows $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-OK "Ponto de restauração criado."
    } catch { Write-Warn "Ponto de restauração não criado: $($_.Exception.Message)" }
}

# ───────────────────────────── Funções reutilizáveis ─────────────────────────────
function Set-Plano([string]$Guid) {
    & powercfg.exe /setactive $Guid
    if ($LASTEXITCODE -ne 0) { throw "Plano de energia indisponível neste dispositivo." }
}

function Set-PlanoMaximo {
    $lista = & powercfg.exe /list | Out-String
    $linha = ($lista -split "`n") | Where-Object { $_ -match 'Ultimate|Desempenho M' } | Select-Object -First 1
    if (-not $linha) {
        $lista = & powercfg.exe -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-String
        $linha = $lista
    }
    if ($linha -match '([0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12})') { Set-Plano $Matches[1] }
    else { Set-Plano 'SCHEME_MIN' }
}

function Disable-UsbSuspend {
    & powercfg.exe /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    & powercfg.exe /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    & powercfg.exe /setactive SCHEME_CURRENT
}

function Set-MouseSemAceleracao {
    Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed'      '0' 'String'
    Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'
    Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String'
}

function Set-Hags([int]$Modo) {   # 2 = ligado, 1 = desligado
    Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' $Modo
    $Script:Reiniciar = $true
}

function Clear-ShaderCache {
    $p = "$env:LOCALAPPDATA\D3DSCache"
    if (Test-Path $p) { Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
}

function Restart-Explorer { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue }

function Clear-Temp {
    $drv = $env:SystemDrive.TrimEnd(':')
    $antes = (Get-PSDrive -Name $drv).Free
    $alvos = @($env:TEMP, "$env:SystemRoot\Temp", "$env:LOCALAPPDATA\Microsoft\Windows\INetCache",
               "$env:LOCALAPPDATA\CrashDumps", "$env:ProgramData\Microsoft\Windows\WER\ReportQueue")
    foreach ($a in $alvos) {
        if (Test-Path $a) {
            Get-ChildItem $a -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Write-Info "Limpo: $a"
        }
    }
    $rodando = (Get-Service wuauserv, bits -ErrorAction SilentlyContinue | Where-Object Status -eq 'Running').Name
    Stop-Service wuauserv, bits -Force -ErrorAction SilentlyContinue
    Get-ChildItem "$env:SystemRoot\SoftwareDistribution\Download" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    foreach ($s in $rodando) { Start-Service $s -ErrorAction SilentlyContinue }
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    $liberado = [math]::Round(((Get-PSDrive -Name $drv).Free - $antes) / 1MB, 1)
    Write-OK "Limpeza concluída. Espaço liberado (aprox.): $liberado MB"
}

# ═══════════════════════════ 1. INICIALIZAÇÃO E DESLIGAMENTO ═══════════════════════════
function Menu-Inicializacao {
    Invoke-Menu '1. Otimização de Inicialização e Desligamento' @(
        @{ N = 'Reduzir tempo de encerramento de serviços e aplicações'; A = {
            Invoke-Step 'Timeout de serviços = 5 s' { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout' '5000' 'String' }
            Invoke-Step 'Timeout de aplicações = 5 s' { Set-Reg 'HKCU:\Control Panel\Desktop' 'WaitToKillAppTimeout' '5000' 'String' }
            Invoke-Step 'Timeout de apps travadas = 4 s' { Set-Reg 'HKCU:\Control Panel\Desktop' 'HungAppTimeout' '4000' 'String' } } },
        @{ N = 'Remover atraso artificial de programas de inicialização'; A = {
            Invoke-Step 'StartupDelayInMSec = 0' { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 0 } } },
        @{ N = 'Ativar Inicialização Rápida (Fast Startup)'; A = {
            Invoke-Step 'Fast Startup ativado' { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 1 } } },
        @{ N = 'Desativar Inicialização Rápida (resolve problemas de drivers/dual boot)'; A = {
            Invoke-Step 'Fast Startup desativado' { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 } } },
        @{ N = 'Listar programas que iniciam com o Windows'; A = {
            Get-CimInstance Win32_StartupCommand | Select-Object Name, Location, Command | Format-Table -AutoSize -Wrap | Out-String -Width 120 | Write-Host } },
        @{ N = 'Abrir Gestor de Tarefas > Aplicações de inicialização'; A = { Start-Process taskmgr.exe -ArgumentList '/0 /startup' } },
        @{ N = 'Mostrar tempo do último arranque'; A = {
            $ev = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 1 -ErrorAction Stop
            $x = [xml]$ev.ToXml()
            $ms = ($x.Event.EventData.Data | Where-Object Name -eq 'BootTime').'#text'
            Write-Info ("Último arranque: {0:N1} s (registado em {1})" -f ([double]$ms / 1000), $ev.TimeCreated) } }
    )
}

# ═══════════════════════════════ 2. ACESSO (DISCO/ARQUIVOS) ═══════════════════════════════
function Menu-Acesso {
    Invoke-Menu '2. Otimização de Acesso (disco e arquivos)' @(
        @{ N = 'Desativar atualização do "último acesso" NTFS (menos escritas)'; A = {
            Invoke-Step 'disablelastaccess = 1' { & fsutil.exe behavior set disablelastaccess 1 | Out-Null } } },
        @{ N = 'Restaurar "último acesso" ao padrão do Windows'; A = {
            Invoke-Step 'disablelastaccess = padrão (2)' { & fsutil.exe behavior set disablelastaccess 2 | Out-Null } } },
        @{ N = 'Verificar estado do TRIM'; A = { & fsutil.exe behavior query DisableDeleteNotify | Write-Host
            Write-Info "0 = TRIM ativo | 1 = TRIM desativado" } },
        @{ N = 'Ativar TRIM (SSD)'; A = { Invoke-Step 'TRIM ativado' { & fsutil.exe behavior set DisableDeleteNotify 0 | Out-Null } } },
        @{ N = 'Ativar suporte a caminhos longos (> 260 caracteres)'; A = {
            Invoke-Step 'LongPathsEnabled = 1' { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 1 } } },
        @{ N = 'Explorador abre em "Este Computador" e sem itens recentes/frequentes'; A = {
            $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
            Invoke-Step 'Abrir em Este Computador' { Set-Reg "$k\Advanced" 'LaunchTo' 1 }
            Invoke-Step 'Ocultar arquivos recentes' { Set-Reg $k 'ShowRecent' 0 }
            Invoke-Step 'Ocultar pastas frequentes' { Set-Reg $k 'ShowFrequent' 0 } } },
        @{ N = 'Limpar histórico de arquivos recentes'; A = {
            Invoke-Step 'Histórico limpo' { Remove-Item "$env:APPDATA\Microsoft\Windows\Recent\*" -Recurse -Force -ErrorAction SilentlyContinue } } }
    )
}

# ═══════════════════════════════════ 3. CONTROLE ENERGÉTICO ═══════════════════════════════════
function Menu-Energia {
    Invoke-Menu '3. Controle Energético' @(
        @{ N = 'Plano: Desempenho Máximo (Ultimate Performance)'; A = { Invoke-Step 'Plano Desempenho Máximo ativo' { Set-PlanoMaximo } } },
        @{ N = 'Plano: Alto Desempenho'; A = { Invoke-Step 'Plano Alto Desempenho ativo' { Set-Plano 'SCHEME_MIN' } } },
        @{ N = 'Plano: Equilibrado (recomendado em portáteis)'; A = { Invoke-Step 'Plano Equilibrado ativo' { Set-Plano 'SCHEME_BALANCED' } } },
        @{ N = 'Plano: Economia de energia'; A = { Invoke-Step 'Plano Economia ativo' { Set-Plano 'SCHEME_MAX' } } },
        @{ N = 'Desativar suspensão seletiva USB'; A = { Invoke-Step 'Suspensão seletiva USB desativada' { Disable-UsbSuspend } } },
        @{ N = 'Desativar hibernação (libera espaço; desativa o Fast Startup)'; A = {
            if (Confirm-Acao 'Confirmar?') { Invoke-Step 'Hibernação desativada' { & powercfg.exe /hibernate off } } } },
        @{ N = 'Ativar hibernação'; A = { Invoke-Step 'Hibernação ativada' { & powercfg.exe /hibernate on } } },
        @{ N = 'Mostrar plano ativo'; A = { & powercfg.exe /getactivescheme | Write-Host } },
        @{ N = 'Gerar relatório de bateria (Ambiente de trabalho)'; A = {
            $f = Join-Path ([Environment]::GetFolderPath('Desktop')) 'relatorio-bateria.html'
            & powercfg.exe /batteryreport /output $f | Out-Null; Write-OK "Relatório: $f" } }
    )
}

# ═════════════════════════════ 4. MEMÓRIA E PROCESSAMENTO ═════════════════════════════
function Menu-Memoria {
    Invoke-Menu '4. Otimização de Memória e Processamento' @(
        @{ N = 'Mostrar uso atual de memória'; A = {
            $os = Get-CimInstance Win32_OperatingSystem
            $t = $os.TotalVisibleMemorySize / 1MB; $l = $os.FreePhysicalMemory / 1MB
            Write-Info ("Total: {0:N1} GB | Livre: {1:N1} GB | Em uso: {2:N0}%" -f $t, $l, (($t - $l) / $t * 100)) } },
        @{ N = 'Top 15 processos por memória'; A = {
            Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 15 Name, Id,
                @{ N = 'RAM (MB)'; E = { [math]::Round($_.WorkingSet64 / 1MB) } },
                @{ N = 'CPU (s)';  E = { [math]::Round($_.CPU, 1) } } | Format-Table -AutoSize | Out-String | Write-Host } },
        @{ N = 'Desativar aplicações em segundo plano (UWP)'; A = {
            Invoke-Step 'Apps em segundo plano desativadas' {
                Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
                Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BackgroundAppGlobalToggle' 0 } } },
        @{ N = 'Garantir arquivo de paginação gerenciado pelo Windows'; A = {
            Invoke-Step 'Pagefile automático' { Set-CimInstance -Query 'SELECT * FROM Win32_ComputerSystem' -Property @{ AutomaticManagedPagefile = $true } } } },
        @{ N = 'Ativar compressão de memória'; A = {
            Invoke-Step 'Compressão de memória ativada' { Enable-MMAgent -MemoryCompression }
            Get-MMAgent | Format-List MemoryCompression, PageCombining | Out-String | Write-Host
            $Script:Reiniciar = $true } },
        @{ N = 'SysMain (Superfetch): desativar - SOMENTE se o sistema está em SSD'; A = {
            Write-Warn "Em SSD o ganho é pequeno; em HDD pode PIORAR o desempenho."
            if (Confirm-Acao 'Desativar SysMain?') { Invoke-Step 'SysMain desativado' { [void](Set-Svc 'SysMain' 'Disabled') } } } },
        @{ N = 'Agendar Diagnóstico de Memória do Windows'; A = { Start-Process mdsched.exe } }
    )
}

# ═══════════════════════════ 5. ACELERAÇÃO DE DRIVES E PERIFÉRICOS ═══════════════════════════
function Menu-Drives {
    Invoke-Menu '5. Aceleração de Drives e Periféricos' @(
        @{ N = 'Identificar discos (SSD/HDD) e estado de saúde'; A = {
            Get-PhysicalDisk | Select-Object FriendlyName, MediaType, HealthStatus, OperationalStatus,
                @{ N = 'GB'; E = { [math]::Round($_.Size / 1GB) } } | Format-Table -AutoSize | Out-String | Write-Host
            try { Get-PhysicalDisk | Get-StorageReliabilityCounter | Select-Object DeviceId, Temperature, Wear, ReadErrorsTotal, WriteErrorsTotal |
                  Format-Table -AutoSize | Out-String | Write-Host } catch {} } },
        @{ N = 'Otimizar volumes (TRIM em SSD / desfragmentar HDD)'; A = {
            foreach ($v in Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter }) {
                $tipo = (Get-Partition -DriveLetter $v.DriveLetter | Get-Disk | Get-PhysicalDisk).MediaType
                Write-Info "Unidade $($v.DriveLetter): ($tipo)"
                if ($tipo -eq 'SSD')     { Optimize-Volume -DriveLetter $v.DriveLetter -ReTrim -Verbose }
                elseif ($tipo -eq 'HDD') { Optimize-Volume -DriveLetter $v.DriveLetter -Defrag -Verbose }
                else { Write-Warn "Tipo de mídia desconhecido - ignorado." }
            } } },
        @{ N = 'Listar dispositivos com problemas / drivers com erro'; A = {
            $d = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object Status -eq 'Error'
            if ($d) { $d | Select-Object FriendlyName, Class, Status | Format-Table -AutoSize | Out-String | Write-Host }
            else { Write-OK 'Nenhum dispositivo com erro.' } } },
        @{ N = 'Procurar alterações de hardware'; A = { Invoke-Step 'Verificação iniciada' { & pnputil.exe /scan-devices | Out-Null } } },
        @{ N = 'Desativar suspensão seletiva USB'; A = { Invoke-Step 'Suspensão seletiva USB desativada' { Disable-UsbSuspend } } },
        @{ N = 'Mouse: desativar aceleração (precisão 1:1; requer novo login)'; A = { Invoke-Step 'Aceleração do mouse desativada' { Set-MouseSemAceleracao } } },
        @{ N = 'Teclado: reduzir atraso e aumentar taxa de repetição'; A = {
            Invoke-Step 'Teclado mais responsivo' {
                Set-Reg 'HKCU:\Control Panel\Keyboard' 'KeyboardDelay' '0' 'String'
                Set-Reg 'HKCU:\Control Panel\Keyboard' 'KeyboardSpeed' '31' 'String' } } }
    )
}

# ═════════════════════════════ 6. REDE E INTERNET ═════════════════════════════
function Set-Dns([string[]]$Servidores) {
    Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | ForEach-Object {
        if ($Servidores) { Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses $Servidores }
        else { Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses }
        Write-Info "Adaptador: $($_.Name)"
    }
    & ipconfig.exe /flushdns | Out-Null
}

function Menu-Rede {
    Invoke-Menu '6. Otimização de Rede e Internet' @(
        @{ N = 'Diagnóstico: adaptadores ativos e latência (Cloudflare/Google)'; A = {
            Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object Name, LinkSpeed, InterfaceDescription | Format-Table -AutoSize | Out-String | Write-Host
            & ping.exe -n 4 1.1.1.1 | Write-Host; & ping.exe -n 4 8.8.8.8 | Write-Host } },
        @{ N = 'Limpar cache DNS'; A = { Invoke-Step 'Cache DNS limpo' { & ipconfig.exe /flushdns | Out-Null } } },
        @{ N = 'Ajustar TCP (auto-tuning normal + RSS ativo)'; A = {
            Invoke-Step 'TCP ajustado' {
                & netsh.exe int tcp set global autotuninglevel=normal | Out-Null
                & netsh.exe int tcp set global rss=enabled | Out-Null }
            & netsh.exe int tcp show global | Write-Host } },
        @{ N = 'DNS: Cloudflare (1.1.1.1 / 1.0.0.1)'; A = { Invoke-Step 'DNS Cloudflare aplicado' { Set-Dns @('1.1.1.1', '1.0.0.1') } } },
        @{ N = 'DNS: Google (8.8.8.8 / 8.8.4.4)'; A = { Invoke-Step 'DNS Google aplicado' { Set-Dns @('8.8.8.8', '8.8.4.4') } } },
        @{ N = 'DNS: voltar ao automático (DHCP)'; A = { Invoke-Step 'DNS automático' { Set-Dns @() } } },
        @{ N = 'Desativar economia de energia nos adaptadores de rede'; A = {
            Get-NetAdapter -Physical | ForEach-Object {
                try { Set-NetAdapterPowerManagement -Name $_.Name -AllowComputerToTurnOffDevice Disabled -ErrorAction Stop; Write-OK $_.Name }
                catch { Write-Warn "$($_.Name): não suportado" } } } },
        @{ N = 'Desativar envio de atualizações a outros PCs (Otimização de Entrega)'; A = {
            Invoke-Step 'Delivery Optimization: apenas HTTP' { Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 } } },
        @{ N = 'Reset completo de rede (Winsock + TCP/IP) - requer reinício'; A = {
            Write-Warn 'Remove configurações de IP estático/VPN personalizadas de baixo nível.'
            if (Confirm-Acao 'Continuar?') {
                Invoke-Step 'Winsock reiniciado' { & netsh.exe winsock reset | Out-Null }
                Invoke-Step 'TCP/IP reiniciado'  { & netsh.exe int ip reset | Out-Null }
                $Script:Reiniciar = $true } } }
    )
}

# ═══════════════════════════════════════ 7. JOGOS ═══════════════════════════════════════
function Menu-Jogos {
    Invoke-Menu '7. Otimização para Jogos' @(
        @{ N = 'APLICAR PERFIL GAMER (Modo de Jogo + sem Game DVR + MMCSS + energia + mouse)'; A = {
            if (-not (Confirm-Acao 'Aplicar perfil completo?')) { return }
            Invoke-Step 'Modo de Jogo ativado' {
                Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
                Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1 }
            Invoke-Step 'Captura em segundo plano desativada' {
                Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
                Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0 }
            Invoke-Step 'Prioridade MMCSS para jogos' {
                $b = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
                Set-Reg $b 'SystemResponsiveness' 10
                Set-Reg "$b\Tasks\Games" 'GPU Priority' 8
                Set-Reg "$b\Tasks\Games" 'Priority' 6
                Set-Reg "$b\Tasks\Games" 'Scheduling Category' 'High' 'String'
                Set-Reg "$b\Tasks\Games" 'SFIO Priority' 'High' 'String' }
            Invoke-Step 'Plano de Desempenho Máximo' { Set-PlanoMaximo }
            Invoke-Step 'Mouse sem aceleração' { Set-MouseSemAceleracao } } },
        @{ N = 'Ativar Modo de Jogo'; A = { Invoke-Step 'Modo de Jogo ativado' {
            Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
            Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1 } } },
        @{ N = 'Desativar Game DVR / captura em segundo plano'; A = { Invoke-Step 'Game DVR desativado' {
            Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
            Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0
            Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' 0 } } },
        @{ N = 'Agendamento de GPU acelerado por hardware (HAGS): ATIVAR'; A = {
            Write-Warn 'Requer GPU/driver compatível (WDDM 2.7+). Reinício necessário.'
            Invoke-Step 'HAGS ativado' { Set-Hags 2 } } },
        @{ N = 'Agendamento de GPU acelerado por hardware (HAGS): DESATIVAR'; A = { Invoke-Step 'HAGS desativado' { Set-Hags 1 } } },
        @{ N = 'Limpar cache de shaders DirectX'; A = { Invoke-Step 'Cache de shaders limpo' { Clear-ShaderCache } } },
        @{ N = 'Dicas finais'; A = {
            Write-Info 'Mantenha os drivers da GPU atualizados (site do fabricante).'
            Write-Info 'Feche navegadores/launchers pesados antes de jogar.'
            Write-Info 'Use o jogo instalado em SSD e mantenha >15% de espaço livre.' } }
    )
}

# ═══════════════════════════════ 8. SERVIÇOS E TELEMETRIA ═══════════════════════════════
$Script:ServicosInuteis = [ordered]@{
    Fax = 'Fax'; RetailDemo = 'Modo demonstração de varejo'; RemoteRegistry = 'Registro remoto (risco de segurança)'
    MapsBroker = 'Mapas transferidos'; WMPNetworkSvc = 'Partilha de rede do Windows Media Player'
    WerSvc = 'Relatório de erros do Windows'; DiagTrack = 'Telemetria (Experiências de Utilizador Ligado)'
    dmwappushservice = 'Roteamento de mensagens WAP Push'
}

function Disable-Telemetria {
    Invoke-Step 'Política de telemetria (nível mínimo)' {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 0
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' 1 }
    Invoke-Step 'Serviços DiagTrack e dmwappushservice' { [void](Set-Svc 'DiagTrack' 'Disabled'); [void](Set-Svc 'dmwappushservice' 'Disabled') }
    Invoke-Step 'Tarefas agendadas de telemetria' {
        Disable-Tarefa '\Microsoft\Windows\Application Experience\' 'Microsoft Compatibility Appraiser'
        Disable-Tarefa '\Microsoft\Windows\Application Experience\' 'ProgramDataUpdater'
        Disable-Tarefa '\Microsoft\Windows\Customer Experience Improvement Program\' 'Consolidator'
        Disable-Tarefa '\Microsoft\Windows\Customer Experience Improvement Program\' 'UsbCeip'
        Disable-Tarefa '\Microsoft\Windows\Customer Experience Improvement Program\' 'KernelCeipTask' }
    Write-Info 'Nota: em edições Home/Pro o Windows mantém o nível mínimo "Necessário" mesmo com valor 0.'
}

function Disable-Privacidade {
    Invoke-Step 'ID de publicidade desativado' {
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
        Set-Reg 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1
        Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_TrackProgs' 0 }
    Invoke-Step 'Sugestões e anúncios do Windows desativados' {
        $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        foreach ($n in 'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
                       'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled', 'SubscribedContent-310093Enabled',
                       'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled', 'RotatingLockScreenOverlayEnabled',
                       'SilentInstalledAppsEnabled', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled') { Set-Reg $k $n 0 } }
}

function Menu-Servicos {
    Invoke-Menu '8. Serviços Desnecessários e Telemetria' @(
        @{ N = 'Desativar telemetria (política + serviços + tarefas agendadas)'; A = { Disable-Telemetria } },
        @{ N = 'Reduzir rastreio de privacidade, publicidade e sugestões'; A = { Disable-Privacidade } },
        @{ N = 'Desativar serviços desnecessários (mostra lista antes)'; A = {
            foreach ($n in $Script:ServicosInuteis.Keys) {
                $s = Get-CimInstance Win32_Service -Filter "Name='$n'" -ErrorAction SilentlyContinue
                if ($s) { Write-Host ("   - {0,-18} {1,-9} {2}" -f $n, $s.StartMode, $Script:ServicosInuteis[$n]) }
            }
            Write-Warn 'Nunca são tocados: Windows Update, Defender, Firewall, Audio, Rede.'
            if (Confirm-Acao 'Desativar os serviços acima?') {
                foreach ($n in $Script:ServicosInuteis.Keys) { if (Set-Svc $n 'Disabled') { Write-OK "Desativado: $n" } } } } },
        @{ N = 'Listar serviços em execução (arranque automático)'; A = {
            Get-Service | Where-Object { $_.Status -eq 'Running' } | Sort-Object DisplayName |
                Select-Object Name, DisplayName | Format-Table -AutoSize | Out-String -Width 120 | Write-Host } },
        @{ N = 'APLICAR TUDO (telemetria + privacidade + serviços)'; A = {
            if (Confirm-Acao 'Aplicar todos os ajustes desta secção?') {
                Disable-Telemetria; Disable-Privacidade
                foreach ($n in $Script:ServicosInuteis.Keys) { [void](Set-Svc $n 'Disabled') }
                Write-OK 'Concluído. Use [R] no menu principal para reverter.' } } }
    )
}

# ═══════════════════════════════════════ 9. GRÁFICA ═══════════════════════════════════════
function Menu-Grafica {
    Invoke-Menu '9. Otimização Gráfica' @(
        @{ N = 'Efeitos visuais equilibrados (sem transparência e animações)'; A = {
            Invoke-Step 'Transparência desativada' { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0 }
            Invoke-Step 'Animações desativadas' {
                Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
                Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0 } } },
        @{ N = 'Restaurar efeitos visuais padrão'; A = {
            Invoke-Step 'Efeitos restaurados' {
                Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1
                Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '1' 'String'
                Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 1 } } },
        @{ N = 'Ativar suavização de fontes ClearType'; A = { Invoke-Step 'ClearType ativo' {
            Set-Reg 'HKCU:\Control Panel\Desktop' 'FontSmoothing' '2' 'String'
            Set-Reg 'HKCU:\Control Panel\Desktop' 'FontSmoothingType' 2 } } },
        @{ N = 'Informações da placa gráfica'; A = {
            Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate, CurrentRefreshRate,
                @{ N = 'VRAM (GB)'; E = { [math]::Round($_.AdapterRAM / 1GB, 1) } } | Format-List | Out-String | Write-Host } },
        @{ N = 'HAGS: ativar (GPU compatível; requer reinício)'; A = { Invoke-Step 'HAGS ativado' { Set-Hags 2 } } },
        @{ N = 'Limpar cache de shaders DirectX'; A = { Invoke-Step 'Cache de shaders limpo' { Clear-ShaderCache } } },
        @{ N = 'Abrir configurações gráficas por aplicação'; A = { Start-Process 'ms-settings:display-advancedgraphics' } }
    )
}

# ═════════════════════════════ 10. INTERFACE E USABILIDADE ═════════════════════════════
function Menu-Interface {
    $clsid = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
    Invoke-Menu '10. Ajuste de Interface e Usabilidade' @(
        @{ N = 'Mostrar extensões de arquivo e arquivos ocultos'; A = {
            Invoke-Step 'Extensões e ocultos visíveis' {
                Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'HideFileExt' 0
                Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Hidden' 1 } } },
        @{ N = 'Reduzir atraso dos menus (400 ms -> 100 ms)'; A = {
            Invoke-Step 'MenuShowDelay = 100' { Set-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '100' 'String' } } },
        @{ N = 'Desativar pesquisa web (Bing) no menu Iniciar'; A = {
            Invoke-Step 'Pesquisa web desativada' { Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1 } } },
        @{ N = 'Desativar atalho das Teclas de Aderência (Shift x5)'; A = {
            Invoke-Step 'Atalho desativado' { Set-Reg 'HKCU:\Control Panel\Accessibility\StickyKeys' 'Flags' '506' 'String' } } },
        @{ N = '[Win11] Menu de contexto clássico (mostrar mais opções direto)'; A = {
            if (-not $Script:EhWin11) { Write-Warn 'Só aplicável ao Windows 11.'; return }
            Invoke-Step 'Menu clássico ativado' { New-Item -Path "$clsid\InprocServer32" -Force -Value '' | Out-Null; Restart-Explorer } } },
        @{ N = '[Win11] Voltar ao menu de contexto padrão do Windows 11'; A = {
            Invoke-Step 'Menu padrão restaurado' { Remove-Item -Path $clsid -Recurse -Force -ErrorAction SilentlyContinue; Restart-Explorer } } },
        @{ N = '[Win11] Barra de tarefas alinhada à esquerda'; A = {
            if (-not $Script:EhWin11) { Write-Warn 'Só aplicável ao Windows 11.'; return }
            Invoke-Step 'Barra à esquerda' { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAl' 0 } } },
        @{ N = '[Win11] Barra de tarefas centralizada (padrão)'; A = {
            Invoke-Step 'Barra ao centro' { Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAl' 1 } } },
        @{ N = 'Reiniciar o Explorador de Arquivos (aplica alterações visuais)'; A = { Invoke-Step 'Explorador reiniciado' { Restart-Explorer } } }
    )
}

# ═════════════════════════════════ 11. CONTROLE DE MANUTENÇÃO ═════════════════════════════════
function Menu-Manutencao {
    Invoke-Menu '11. Controle de Manutenção' @(
        @{ N = 'Limpar arquivos temporários, cache de updates e lixeira'; A = { Clear-Temp } },
        @{ N = 'Reparar arquivos do sistema (DISM RestoreHealth + SFC) - demorado'; A = {
            Write-Info 'A executar DISM...'; & DISM.exe /Online /Cleanup-Image /RestoreHealth
            Write-Info 'A executar SFC...';  & sfc.exe /scannow } },
        @{ N = 'Verificar o disco do sistema (CHKDSK online, sem reiniciar)'; A = { & chkdsk.exe "$env:SystemDrive" /scan } },
        @{ N = 'Limpar componentes antigos do Windows (WinSxS)'; A = { & DISM.exe /Online /Cleanup-Image /StartComponentCleanup } },
        @{ N = 'Criar ponto de restauração agora'; A = { New-Restore } },
        @{ N = 'Ver espaço livre em disco'; A = {
            Get-Volume | Where-Object DriveLetter | Select-Object DriveLetter, FileSystemLabel,
                @{ N = 'Total GB'; E = { [math]::Round($_.Size / 1GB, 1) } },
                @{ N = 'Livre GB'; E = { [math]::Round($_.SizeRemaining / 1GB, 1) } } | Format-Table -AutoSize | Out-String | Write-Host } },
        @{ N = 'Ver últimas linhas do log deste programa'; A = {
            if (Test-Path $Script:LogFile) { Get-Content $Script:LogFile -Tail 25 -Encoding UTF8 | Write-Host } else { Write-Info 'Log vazio.' } } }
    )
}

# ═══════════════════════════════ 12. EXPANSÃO DE MANUTENÇÃO ═══════════════════════════════
function Menu-Expansao {
    $tarefa = 'OtimizadorWindows-ManutencaoSemanal'
    Invoke-Menu '12. Expansão de Manutenção (automação e relatórios)' @(
        @{ N = 'Agendar limpeza semanal automática (domingo 03:00)'; A = {
            Invoke-Step 'Tarefa agendada criada' {
                $s = Join-Path $Script:Pasta 'ManutencaoSemanal.ps1'
                @'
$limite = (Get-Date).AddDays(-7)
$alvos = @("$env:SystemRoot\Temp") + (Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue | ForEach-Object { "$($_.FullName)\AppData\Local\Temp" })
foreach ($a in $alvos) {
    if (Test-Path $a) {
        Get-ChildItem $a -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object LastWriteTime -lt $limite | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}
Clear-RecycleBin -Force -ErrorAction SilentlyContinue
'@ | Set-Content -Path $s -Encoding UTF8
                $acao = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$s`""
                $trig = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
                $prin = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest
                $conf = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries
                Register-ScheduledTask -TaskName $tarefa -Action $acao -Trigger $trig -Principal $prin -Settings $conf -Force | Out-Null } } },
        @{ N = 'Remover a limpeza semanal agendada'; A = {
            Invoke-Step 'Tarefa removida' { Unregister-ScheduledTask -TaskName $tarefa -Confirm:$false } } },
        @{ N = 'Ativar Sensor de Armazenamento (limpeza automática do Windows)'; A = {
            Invoke-Step 'Sensor de Armazenamento ativo' {
                $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'
                Set-Reg $k '01' 1; Set-Reg $k '04' 1; Set-Reg $k '08' 1; Set-Reg $k '256' 30; Set-Reg $k '2048' 7 } } },
        @{ N = 'Executar a Manutenção Automática do Windows agora'; A = {
            Invoke-Step 'Manutenção Automática iniciada' {
                Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Schedule\Maintenance' 'MaintenanceDisabled' 0
                & MSchedExe.exe Start } } },
        @{ N = 'Atualizar programas instalados (winget)'; A = {
            if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Write-Warn 'winget não encontrado (instale o "App Installer").'; return }
            if (Confirm-Acao 'Atualizar todos os programas?') {
                & winget.exe upgrade --all --include-unknown --accept-source-agreements --accept-package-agreements } } },
        @{ N = 'Abrir Windows Update'; A = { Start-Process 'ms-settings:windowsupdate' } },
        @{ N = 'Relatório de eficiência energética (60 s)'; A = {
            $f = Join-Path ([Environment]::GetFolderPath('Desktop')) 'relatorio-energia.html'
            Write-Info 'A recolher dados durante 60 segundos...'
            & powercfg.exe /energy /duration 60 /output $f | Out-Null; Write-OK "Relatório: $f" } },
        @{ N = 'Gerar relatório do sistema (Ambiente de trabalho)'; A = {
            $f = Join-Path ([Environment]::GetFolderPath('Desktop')) "relatorio-sistema-$(Get-Date -Format 'yyyyMMdd-HHmm').txt"
            $os = Get-CimInstance Win32_OperatingSystem; $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
            @(
                "RELATÓRIO DO SISTEMA - $(Get-Date)"; "=" * 60
                "PC: $env:COMPUTERNAME"; "SO: $($os.Caption) (build $($os.BuildNumber))"
                "CPU: $($cpu.Name) ($($cpu.NumberOfCores) núcleos)"
                ("RAM: {0:N1} GB" -f ($os.TotalVisibleMemorySize / 1MB))
                "Último arranque: $($os.LastBootUpTime)"
                ""; "DISCOS:"
                (Get-PhysicalDisk | ForEach-Object { "  $($_.FriendlyName) | $($_.MediaType) | $($_.HealthStatus)" })
                ""; "GPU:"
                (Get-CimInstance Win32_VideoController | ForEach-Object { "  $($_.Name) | driver $($_.DriverVersion)" })
                ""; "ÚLTIMAS ATUALIZAÇÕES:"
                (Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 10 | ForEach-Object { "  $($_.HotFixID) - $($_.InstalledOn)" })
            ) | Set-Content -Path $f -Encoding UTF8
            Write-OK "Relatório: $f" } }
    )
}

# ═══════════════════════════════════════ MENU PRINCIPAL ═══════════════════════════════════════
function Show-Principal {
    Show-Header
    $os = Get-CimInstance Win32_OperatingSystem
    $t = $os.TotalVisibleMemorySize / 1MB; $l = $os.FreePhysicalMemory / 1MB
    Write-Host ("  PC: {0}  |  {1}" -f $env:COMPUTERNAME, $os.Caption) -ForegroundColor Gray
    Write-Host ("  RAM: {0:N1}/{1:N1} GB livres  |  Privilégios: Administrador ✔" -f $l, $t) -ForegroundColor Gray
    Write-Host ("  " + ('─' * ($Script:Largura - 2))) -ForegroundColor DarkGray
    $m = @('Otimização de Inicialização e Desligamento', 'Otimização de Acesso (disco e arquivos)', 'Controle Energético',
           'Otimização de Memória e Processamento', 'Aceleração de Drives e Periféricos', 'Otimização de Rede e Internet',
           'Otimização para Jogos', 'Serviços Desnecessários e Telemetria', 'Otimização Gráfica',
           'Ajuste de Interface e Usabilidade', 'Controle de Manutenção', 'Expansão de Manutenção')
    for ($i = 0; $i -lt $m.Count; $i++) { Write-Host ("   [{0,2}] {1}" -f ($i + 1), $m[$i]) -ForegroundColor White }
    Write-Host ""
    Write-Host "   [ R] Reverter alterações feitas por este programa" -ForegroundColor Yellow
    Write-Host "   [ P] Criar ponto de restauração" -ForegroundColor Yellow
    Write-Host "   [ 0] Sair" -ForegroundColor DarkGray
}

Show-Header 'Bem-vindo'
Write-Info "Cada alteração é registada e pode ser revertida pela opção [R]."
if (Confirm-Acao 'Criar um ponto de restauração antes de começar? (recomendado)') { New-Restore; Start-Sleep 1 }

$sair = $false
while (-not $sair) {
    Show-Principal
    switch ((Read-Host "`n  Escolha uma opção").Trim().ToUpper()) {
        '1'  { Menu-Inicializacao } '2'  { Menu-Acesso }    '3'  { Menu-Energia }
        '4'  { Menu-Memoria }       '5'  { Menu-Drives }    '6'  { Menu-Rede }
        '7'  { Menu-Jogos }         '8'  { Menu-Servicos }  '9'  { Menu-Grafica }
        '10' { Menu-Interface }     '11' { Menu-Manutencao } '12' { Menu-Expansao }
        'R'  { Show-Header 'Reverter alterações'; Restore-All; Pausar }
        'P'  { Show-Header 'Ponto de restauração'; New-Restore; Pausar }
        '0'  { $sair = $true }
    }
}

Show-Header
if ($Script:Reiniciar) {
    Write-Warn 'Algumas alterações só terão efeito após reiniciar o computador.'
    if (Confirm-Acao 'Reiniciar agora?') { Restart-Computer -Force }
}
Write-Info "Log: $Script:LogFile"
Write-Host "`n  Até logo!`n" -ForegroundColor Cyan
