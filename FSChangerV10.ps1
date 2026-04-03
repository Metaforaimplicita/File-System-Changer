# ====================================================================
# HERRAMIENTA DE FORMATEO TACTICO V10.0 - EDICION FINAL INTEGRAL
# ====================================================================

# 0. PROTOCOLO DE AUTO-ELEVACION
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "===================================================" -ForegroundColor Red
    Write-Host " [ACCESO DENEGADO] SOLICITANDO PRIVILEGIOS ADMIN... " -ForegroundColor Red
    Write-Host "===================================================" -ForegroundColor Red
    Start-Process PowerShell -Verb RunAs "-NoProfile -ExecutionPolicy Bypass -Command `"cd '$pwd'; & '$PSCommandPath';`""
    exit
}

Clear-Host
Write-Host "[*] INICIANDO PROTOCOLO DE RECONOCIMIENTO..." -ForegroundColor Cyan

# 1. AUDITORIA Y DESPLIEGUE SILENCIOSO DE WSL
wsl --set-default-version 2 > $null 2>&1
$distros = wsl --list --quiet 2>$null
if (-not ($distros -match "kali-linux")) {
    Write-Host "[!] Motor Linux ausente. Desplegando Kali en segundo plano..." -ForegroundColor Yellow
    wsl --install -d kali-linux --web-download --no-launch
    wsl -d kali-linux -u root -e ls > $null
}

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "   NUCLEO DE GESTION DE ALMACENAMIENTO V10.0 (FINAL)  " -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan

# 2. ESCANEO FISICO DE HARDWARE
Write-Host "Escaneando discos (Ignorando capas logicas de Windows)..." -ForegroundColor Green
Get-Disk | Sort-Object Number | Select-Object Number, FriendlyName, @{Name="Size(GB)";Expression={[math]::Round($_.Size/1GB,2)}}, PartitionStyle, BusType | Format-Table -AutoSize

$diskNum = Read-Host "Ingresa el NUMERO del disco a intervenir"
$disco = Get-Disk -Number $diskNum -ErrorAction SilentlyContinue

if (!$disco -or $disco.IsBoot -or $disco.IsSystem) {
    Write-Host "[ERROR] Seleccion no valida o protegida por el sistema." -ForegroundColor Red
    Start-Sleep -Seconds 5 ; exit
}

$tamanoGB = [math]::Round($disco.Size / 1GB, 2)

# 3. SELECCION DE ARQUITECTURA (GPT vs MBR)
Write-Host "`nSELECCIONA EL ESTILO DE PARTICION:" -ForegroundColor Yellow
Write-Host "1. GPT (Moderno: Recomendado para UEFI y discos >2TB)"
Write-Host "2. MBR (Legacy: Para hardware antiguo y maxima compatibilidad)"
$opcionEstilo = Read-Host "Ingresa 1 o 2"
$styleCmd = if ($opcionEstilo -eq "2") { "convert mbr" } else { "convert gpt" }

# 4. SELECCION DE SISTEMA DE ARCHIVOS Y FAMILIA EXT
Write-Host "`nSELECCIONA EL SISTEMA DE ARCHIVOS OBJETIVO:" -ForegroundColor Yellow
Write-Host "1. FAT32 (Compatibilidad universal)"
Write-Host "2. exFAT (Ideal para memorias >32GB / T-Deck)"
Write-Host "3. NTFS  (Nativo de Windows)"
Write-Host "4. FAMILIA EXT (EXT2, EXT3, EXT4 via WSL)"
$opcionFS = Read-Host "Ingresa el numero de tu opcion"

$fileSys = "exfat"
$sizeParam = ""
$extType = "ext4"

if ($opcionFS -eq "1") {
    $fileSys = "fat32"
    if ($tamanoGB -gt 32) {
        Write-Host "`n[ADVERTENCIA] Unidad mayor a 32GB." -ForegroundColor Red
        Write-Host "A. Limitar a 32GB (Particion Tactica)"
        Write-Host "B. Forzar capacidad completa ($tamanoGB GB)"
        if ((Read-Host "Ingresa A o B") -eq "A") { $sizeParam = "size=32768" }
    }
} elseif ($opcionFS -eq "3") { 
    $fileSys = "ntfs" 
} elseif ($opcionFS -eq "4") {
    Write-Host "`nSELECCIONA LA VARIANTE EXT:" -ForegroundColor Cyan
    Write-Host "A. EXT4 (Estandar moderno / Rapido)"
    Write-Host "B. EXT3 (Con journaling para seguridad)"
    Write-Host "C. EXT2 (Sin journaling / Protege memorias Flash)"
    $opcExt = Read-Host "Ingresa A, B o C"
    if ($opcExt.ToUpper() -eq "B") { $extType = "ext3" }
    elseif ($opcExt.ToUpper() -eq "C") { $extType = "ext2" }
}

# 5. SEGURO DE IGNICION
Write-Host "`n===================================================" -ForegroundColor Red
Write-Host "¡ALERTA DE PURGA! DISCO $($disco.Number) - $tamanoGB GB" -ForegroundColor Red
Write-Host "===================================================" -ForegroundColor Red
if ((Read-Host "Escribe 'PURGAR' para confirmar") -cne "PURGAR") { exit }

# 6. EJECUCION DE MOTORES
Write-Host "`n[+] Iniciando secuencia de destruccion y reconstruccion..." -ForegroundColor Yellow

if ($opcionFS -eq "4") {
    # RUTINA EXT (WSL HIBRIDO)
    if ($disco.BusType -eq "USB") {
        Write-Host "[X] ERROR: Microsoft bloquea el montaje USB directo para la familia EXT." -ForegroundColor Red
        Write-Host "Sugerencia: Usa exFAT (Opcion 2) para esta memoria externa." -ForegroundColor Yellow
        Start-Sleep -Seconds 5 ; exit
    }
    Set-Disk -Number $disco.Number -IsOffline $true
    $diskPath = "\\.\PhysicalDrive$($disco.Number)"
    
    # Montaje bare para acceso directo al bloque
    wsl --mount $diskPath --bare
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[X] Error al montar. Restaurando disco..." -ForegroundColor Red
        Set-Disk -Number $disco.Number -IsOffline $false ; exit
    }

    Write-Host "Dispositivos detectados en Linux:" -ForegroundColor Yellow
    wsl -d kali-linux -u root -e lsblk
    $linuxDev = Read-Host "Identifica el dispositivo (Ej: sdc)"
    
    Write-Host "[+] Formateando como $extType..." -ForegroundColor Cyan
    wsl -d kali-linux -u root -e mkfs.$extType /dev/$linuxDev
    
    wsl --unmount $diskPath
    Set-Disk -Number $disco.Number -IsOffline $false
} else {
    # RUTINA NATIVA (DISKPART)
    $dpScript = @"
select disk $($disco.Number)
clean
$styleCmd
create partition primary $sizeParam
format fs=$fileSys quick
assign
"@
    $dpScript | diskpart > $null
}

Write-Host "`n===================================================" -ForegroundColor Green
Write-Host " PROCESO COMPLETADO: EL HARDWARE ESTA OPERATIVO " -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
Start-Sleep -Seconds 5