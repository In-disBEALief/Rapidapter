# Rapidapter.ps1
# Simple IPv4 profile switcher GUI for a selected adapter.
# Run as Administrator.

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---- Theme ----
$Theme = @{
    Back        = [System.Drawing.Color]::FromArgb(32, 32, 32)
    Panel       = [System.Drawing.Color]::FromArgb(40, 40, 40)
    Button      = [System.Drawing.Color]::FromArgb(55, 55, 55)
    ButtonHover = [System.Drawing.Color]::FromArgb(70, 70, 70)
    Border      = [System.Drawing.Color]::FromArgb(90, 90, 90)
    Text        = [System.Drawing.Color]::FromArgb(230, 230, 230)
    SubtleText  = [System.Drawing.Color]::FromArgb(160, 160, 160)
    Accent      = [System.Drawing.Color]::FromArgb(80, 160, 255) # blue
}


# Ensures the program is run with sufficient privileges to change the adapter settings.
function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please run this script as Administrator (required to change IP settings).",
            "Admin Required",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        exit 1
    }
}

# Convert a subnet mask to CIDR notation -- as well as catches malformed masks. 
function MaskToPrefix([string]$mask) {
    # e.g. 255.255.0.0 -> 16
    $parts = $mask.Split('.') | ForEach-Object { [int]$_ }
    if ($parts.Count -ne 4) { throw "Invalid netmask: $mask" }
    $bin = ($parts | ForEach-Object { [Convert]::ToString($_,2).PadLeft(8,'0') }) -join ''
    if ($bin -notmatch '^1*0*$') { throw "Netmask is not contiguous: $mask" }
    return ($bin.ToCharArray() | Where-Object { $_ -eq '1' }).Count
}


# Remove existing IPv4 addresses (except link-local) using netsh delete
function Clear-IPv4([string]$iface) {
    $ips = Get-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
           Where-Object { $_.IPAddress -notlike '169.254.*' }

    foreach ($ip in $ips) {
        try {
            & netsh interface ipv4 delete address name="$iface" address=$ip.IPAddress | Out-Null
        } catch {}
    }

    # Remove default gateway route if present
    try { & netsh interface ipv4 delete route 0.0.0.0/0 "$iface" | Out-Null } catch {}
}

# Set static IPv4 Addres
function Set-StaticIPv4 {
    param(
        [Parameter(Mandatory=$true)][string]$iface,
        [Parameter(Mandatory=$true)][string]$ip,
        [Parameter(Mandatory=$true)][int]$prefix,
        [string]$gateway = $null
    )

    # Convert prefix to dotted netmask
    function PrefixToMask([int]$p){
        $bits = ("1" * $p).PadRight(32,"0")
        $octets = @()
        for ($i=0; $i -lt 32; $i+=8) {
            $octets += [Convert]::ToInt32($bits.Substring($i,8),2)
        }
        return ($octets -join ".")
    }

    $mask = PrefixToMask $prefix

    # Force DHCP off via netsh, then clear and set static
    & netsh interface ipv4 set address name="$iface" source=static address=$ip mask=$mask gateway=none | Out-Null

    Clear-IPv4 $iface

    if ([string]::IsNullOrWhiteSpace($gateway)) {
        & netsh interface ipv4 set address name="$iface" source=static address=$ip mask=$mask gateway=none | Out-Null
    } else {
        & netsh interface ipv4 set address name="$iface" source=static address=$ip mask=$mask gateway=$gateway gwmetric=1 | Out-Null
    }
}

# Set adapter to recieve IPv4 automatically
function Set-DHCP {
    param([Parameter(Mandatory=$true)][string]$iface)

    Clear-IPv4 $iface

    & netsh interface ipv4 set address name="$iface" source=dhcp | Out-Null
    & netsh interface ipv4 set dnsservers name="$iface" source=dhcp | Out-Null
}

# Toast message box
function Show-Toast([string]$msg, [string]$title="A message from Rapidapter!") {
    [System.Windows.Forms.MessageBox]::Show($msg, $title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}


Assert-Admin

# -------- Main Form --------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Rapidly adapt your adapter with Rapidapter today!"
$form.Size = New-Object System.Drawing.Size(520, 540)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = $Theme.Back
$form.ForeColor = $Theme.Text

$font = New-Object System.Drawing.Font("Segoe UI", 10)
$mono = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Bold)

# ---- Header: image + ASCII title ----
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Location = New-Object System.Drawing.Point(0,0)
$headerPanel.Size = New-Object System.Drawing.Size(520, 110)
$headerPanel.BackColor = $Theme.Panel
$form.Controls.Add($headerPanel)

$picLogo = New-Object System.Windows.Forms.PictureBox
$picLogo.Location = New-Object System.Drawing.Point(15, 10)
$picLogo.Size = New-Object System.Drawing.Size(90, 90)
$picLogo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$picLogo.BackColor = [System.Drawing.Color]::Transparent

$logoPath = Join-Path $PSScriptRoot "assets\rapidapter_96.png"
if (Test-Path $logoPath) {
    $picLogo.Image = [System.Drawing.Image]::FromFile($logoPath)
}

$headerPanel.Controls.Add($picLogo)

$lblAscii = New-Object System.Windows.Forms.Label
$lblAscii.Location = New-Object System.Drawing.Point(120, 10)
$lblAscii.Size = New-Object System.Drawing.Size(380, 95)
$lblAscii.Font = $mono
$lblAscii.BackColor = [System.Drawing.Color]::Black
$lblAscii.ForeColor = [System.Drawing.Color]::Gold
$lblAscii.Text = @"                
                 _    __          __         
  _______  ___  (_)__/ /__  ___  / /____ ____
 / __/ _  / _ \/ / _  / _  / _ \/ __/ -_) __/
/_/  \_,_/ .__/_/\_,_/\_,_/ .__/\__/\__/_/   
        /_/              /_/                
"@
$headerPanel.Controls.Add($lblAscii)

# ---- Adapter row ----
$lblAdapter = New-Object System.Windows.Forms.Label
$lblAdapter.Text = "Adapter:"
$lblAdapter.Location = New-Object System.Drawing.Point(15, 125)
$lblAdapter.Size = New-Object System.Drawing.Size(80, 25)
$lblAdapter.Font = $font
$form.Controls.Add($lblAdapter)

$cmbAdapter = New-Object System.Windows.Forms.ComboBox
$cmbAdapter.DropDownStyle = "DropDownList"
$cmbAdapter.Location = New-Object System.Drawing.Point(95, 122)
$cmbAdapter.Size = New-Object System.Drawing.Size(390, 30)
$cmbAdapter.Font = $font
$cmbAdapter.BackColor = $Theme.Panel
$cmbAdapter.ForeColor = $Theme.Text
$form.Controls.Add($cmbAdapter)

function Refresh-Adapters {
    $cmbAdapter.Items.Clear()
    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
                Where-Object { $_.Status -ne "Disabled" } |
                Sort-Object -Property Status, Name
    foreach ($a in $adapters) { $cmbAdapter.Items.Add($a.Name) | Out-Null }
    if ($cmbAdapter.Items.Count -gt 0) { $cmbAdapter.SelectedIndex = 0 }
}
Refresh-Adapters

# Buttons layout helper
function New-Button($text, $x, $y, $w=470, $h=45) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.Font = $font
    $b.FlatStyle = 'Flat'
    $b.UseVisualStyleBackColor = $false
    $b.BackColor = $Theme.Button
    $b.ForeColor = $Theme.Text
    $b.FlatAppearance.BorderColor = $Theme.Border
    $b.FlatAppearance.BorderSize = 1

    # Hover effect (IMPORTANT: use sender param, not $_)
    $b.Add_MouseEnter({ param($sender, $e) $sender.BackColor = $Theme.ButtonHover })
    $b.Add_MouseLeave({ param($sender, $e) $sender.BackColor = $Theme.Button })


    return $b
}


# ---- Buttons ----
$btnDHCP    = New-Button "DHCP (Get IP Automatically)" 15 160

# Separator under DHCP
$sep = New-Object System.Windows.Forms.Panel
$sep.Location = New-Object System.Drawing.Point(15, 212)
$sep.Size = New-Object System.Drawing.Size(470, 2)
$sep.BackColor = $Theme.Border
$sep.BorderStyle = 'None'

$btnPS      = New-Button "MPU-5 MGMT  : 10.3.1.10/24" 15 225
$btnSilvus  = New-Button "Silvus MGMT : 172.16.0.10/16" 15 280
$btnLEMR    = New-Button "LEMR        : 10.30.0.X/24" 15 335
# LEMR octet controls moved BELOW the buttons
$lblOct = New-Object System.Windows.Forms.Label
$lblOct.Text = "LEMR last octet (X):"
$lblOct.Location = New-Object System.Drawing.Point(15, 390)
$lblOct.Size = New-Object System.Drawing.Size(160, 25)
$lblOct.Font = $font

$btnManual  = New-Button "Set Manually" 15 425

$txtOct = New-Object System.Windows.Forms.TextBox
$txtOct.Location = New-Object System.Drawing.Point(180, 387)
$txtOct.Size = New-Object System.Drawing.Size(60, 30)
$txtOct.BackColor = $Theme.Panel
$txtOct.ForeColor = $Theme.Text
$txtOct.Font = $font
$txtOct.Text = "10"

$lblFooter = New-Object System.Windows.Forms.Label
$lblFooter.Text = "A Digital Solution from beal.digital"
$lblFooter.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblFooter.ForeColor = $Theme.SubtleText
$lblFooter.AutoSize = $true
$lblFooter.Location = New-Object System.Drawing.Point(
    ($form.ClientSize.Width - 200),
    ($form.ClientSize.Height - 22)
)
$lblFooter.Cursor = 'Hand'
$lblFooter.Add_Click({ Start-Process "https://beal.digital" })


$form.Controls.Add($lblFooter)


$form.Controls.AddRange(@(
    $btnDHCP, $sep,
    $btnPS, $btnSilvus, $btnLEMR, $btnManual,
    $lblOct, $txtOct
))

# Manual form
function Show-ManualForm([string]$iface) {
    $mf = New-Object System.Windows.Forms.Form
    $mf.Text = "Manual Rapidapter"
    $mf.Size = New-Object System.Drawing.Size(420, 230)
    $mf.StartPosition = "CenterParent"
    $mf.FormBorderStyle = "FixedDialog"
    $mf.MaximizeBox = $false
    $mf.BackColor = $Theme.Back
    $mf.ForeColor = $Theme.Text

    $l1 = New-Object System.Windows.Forms.Label
    $l1.Text = "IPv4 address:"
    $l1.Location = New-Object System.Drawing.Point(15, 20)
    $l1.Size = New-Object System.Drawing.Size(120, 25)
    $l1.Font = $font

    $tIP = New-Object System.Windows.Forms.TextBox
    $tIP.Location = New-Object System.Drawing.Point(140, 18)
    $tIP.Size = New-Object System.Drawing.Size(250, 30)
    $tIP.Font = $font

    $l2 = New-Object System.Windows.Forms.Label
    $l2.Text = "Prefix or netmask:"
    $l2.Location = New-Object System.Drawing.Point(15, 60)
    $l2.Size = New-Object System.Drawing.Size(120, 25)
    $l2.Font = $font

    $tMask = New-Object System.Windows.Forms.TextBox
    $tMask.Location = New-Object System.Drawing.Point(140, 58)
    $tMask.Size = New-Object System.Drawing.Size(250, 30)
    $tMask.Font = $font
    $tMask.PlaceholderText = "Example: 24   or   255.255.255.0"

    $l3 = New-Object System.Windows.Forms.Label
    $l3.Text = "Gateway (opt):"
    $l3.Location = New-Object System.Drawing.Point(15, 100)
    $l3.Size = New-Object System.Drawing.Size(120, 25)
    $l3.Font = $font

    $tGW = New-Object System.Windows.Forms.TextBox
    $tGW.Location = New-Object System.Drawing.Point(140, 98)
    $tGW.Size = New-Object System.Drawing.Size(250, 30)
    $tGW.Font = $font

    $apply = New-Object System.Windows.Forms.Button
    $apply.Text = "Apply"
    $apply.Location = New-Object System.Drawing.Point(140, 140)
    $apply.Size = New-Object System.Drawing.Size(120, 40)
    $apply.Font = $font

    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = "Cancel"
    $cancel.Location = New-Object System.Drawing.Point(270, 140)
    $cancel.Size = New-Object System.Drawing.Size(120, 40)
    $cancel.Font = $font

    $mf.Controls.AddRange(@($l1,$tIP,$l2,$tMask,$l3,$tGW,$apply,$cancel))

    $cancel.Add_Click({ $mf.Close() })

    $apply.Add_Click({
        try {
            $ip = $tIP.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($ip)) { throw "IP address is required." }

            $maskRaw = $tMask.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($maskRaw)) { throw "Prefix/netmask is required." }

            $prefix = 0
            if ($maskRaw -match '^\d+$') {
                $prefix = [int]$maskRaw
            } else {
                $prefix = MaskToPrefix $maskRaw
            }
            if ($prefix -lt 1 -or $prefix -gt 32) { throw "Prefix length must be 1 to 32." }

            $gw = $tGW.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($gw)) { $gw = $null }

            Set-StaticIPv4 -iface $iface -ip $ip -prefix $prefix -gateway $gw
            Show-Toast "Set $iface to $ip/$prefix" "Manual Applied"
            $mf.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            ) | Out-Null
        }
    })

    $mf.ShowDialog($form) | Out-Null
}

# Button handlers
$btnDHCP.Add_Click({
    $iface = $cmbAdapter.SelectedItem
    if (-not $iface) { return }
    try {
        Set-DHCP -iface $iface
        Show-Toast "Set $iface to DHCP (IP + DNS automatic)."
    } catch { Show-Toast $_.Exception.Message "Error" }
})

$btnPS.Add_Click({
    $iface = $cmbAdapter.SelectedItem
    if (-not $iface) { return }
    try {
        Set-StaticIPv4 -iface $iface -ip "10.3.1.10" -prefix 24
        Show-Toast "Set $iface to 10.3.1.10/24 (Persistent Systems)."
    } catch { Show-Toast $_.Exception.Message "Error" }
})

$btnSilvus.Add_Click({
    $iface = $cmbAdapter.SelectedItem
    if (-not $iface) { return }
    try {
        Set-StaticIPv4 -iface $iface -ip "172.16.0.10" -prefix 16
        Show-Toast "Set $iface to 172.16.0.10/16 (Silvus)."
    } catch { Show-Toast $_.Exception.Message "Error" }
})

$btnLEMR.Add_Click({
    $iface = $cmbAdapter.SelectedItem
    if (-not $iface) { return }
    try {
        $oct = [int]($txtOct.Text.Trim())
        if ($oct -lt 2 -or $oct -gt 254) { throw "LEMR last octet must be 2 to 254." }
        $ip = "10.30.0.$oct"
        Set-StaticIPv4 -iface $iface -ip $ip -prefix 24 -gateway "10.30.0.1"
        Show-Toast "Set $iface to $ip/24 with GW 10.30.0.1 (LEMR)."
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
})

$btnManual.Add_Click({
    $iface = $cmbAdapter.SelectedItem
    if (-not $iface) { return }
    Show-ManualForm -iface $iface
})

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
