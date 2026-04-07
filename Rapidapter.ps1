# Rapidapter.ps1
# IPv4 profile switcher GUI - select an adapter and apply a preset.

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
    Accent      = [System.Drawing.Color]::FromArgb(80, 160, 255)
    AccentDark  = [System.Drawing.Color]::FromArgb(30, 80, 140)
    AccentHover = [System.Drawing.Color]::FromArgb(45, 105, 175)
}

# Re-launch the script elevated if not already running as administrator.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    exit
}

# Convert a subnet mask to CIDR prefix length.
function MaskToPrefix([string]$mask) {
    $parts = $mask.Split('.') | ForEach-Object { [int]$_ }
    if ($parts.Count -ne 4) { throw "Invalid netmask: $mask" }
    $bin = ($parts | ForEach-Object { [Convert]::ToString($_, 2).PadLeft(8, '0') }) -join ''
    if ($bin -notmatch '^1*0*$') { throw "Netmask is not contiguous: $mask" }
    return ($bin.ToCharArray() | Where-Object { $_ -eq '1' }).Count
}

# Convert a CIDR prefix length to dotted subnet mask.
function PrefixToMask([int]$p) {
    $bits = ("1" * $p).PadRight(32, "0")
    $octets = @()
    for ($i = 0; $i -lt 32; $i += 8) {
        $octets += [Convert]::ToInt32($bits.Substring($i, 8), 2)
    }
    return ($octets -join ".")
}

# Remove existing IPv4 addresses (except link-local).
function Clear-IPv4([string]$iface) {
    $ips = Get-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
           Where-Object { $_.IPAddress -notlike '169.254.*' }
    foreach ($ip in $ips) {
        try { & netsh interface ipv4 delete address name="$iface" address=$ip.IPAddress | Out-Null } catch {}
    }
    try { & netsh interface ipv4 delete route 0.0.0.0/0 "$iface" | Out-Null } catch {}
}

# Set a static IPv4 address with optional gateway and DNS.
function Set-StaticIPv4 {
    param(
        [Parameter(Mandatory)][string]$iface,
        [Parameter(Mandatory)][string]$ip,
        [Parameter(Mandatory)][int]$prefix,
        [string]$gateway,
        [string]$dns
    )
    $mask = PrefixToMask $prefix
    & netsh interface ipv4 set address name="$iface" source=static address=$ip mask=$mask gateway=none | Out-Null
    Clear-IPv4 $iface
    if ([string]::IsNullOrWhiteSpace($gateway)) {
        & netsh interface ipv4 set address name="$iface" source=static address=$ip mask=$mask gateway=none | Out-Null
    } else {
        & netsh interface ipv4 set address name="$iface" source=static address=$ip mask=$mask gateway=$gateway gwmetric=1 | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($dns)) {
        & netsh interface ipv4 set dnsservers name="$iface" source=static address=$dns validate=no | Out-Null
    }
}

# Set adapter to receive IPv4 automatically.
function Set-DHCP([string]$iface) {
    Clear-IPv4 $iface
    & netsh interface ipv4 set address name="$iface" source=dhcp | Out-Null
    & netsh interface ipv4 set dnsservers name="$iface" source=dhcp | Out-Null
}

function Show-Toast([string]$msg, [string]$title = "Rapidapter") {
    [System.Windows.Forms.MessageBox]::Show($msg, $title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

# ---- Preset persistence ----
$script:PresetsPath = Join-Path $PSScriptRoot "presets.json"

function Import-Presets {
    if (-not (Test-Path $script:PresetsPath)) { return @() }
    try {
        return @((Get-Content $script:PresetsPath -Raw | ConvertFrom-Json).presets)
    } catch { return @() }
}

function Save-Presets([array]$presets) {
    @{ presets = $presets } | ConvertTo-Json -Depth 4 | Set-Content $script:PresetsPath -Encoding UTF8
}

# -------- Main Form --------
$form = New-Object System.Windows.Forms.Form
$form.Text = "Rapidly adapt your adapter with Rapidapter today!"
$form.Size = New-Object System.Drawing.Size(535, 580)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = $Theme.Back
$form.ForeColor = $Theme.Text

$font   = New-Object System.Drawing.Font("Segoe UI", 10)
$fontSm = New-Object System.Drawing.Font("Segoe UI", 9)
$mono   = New-Object System.Drawing.Font("Consolas", 11, [System.Drawing.FontStyle]::Bold)

# ---- Header ----
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Location = New-Object System.Drawing.Point(0, 0)
$headerPanel.Size = New-Object System.Drawing.Size(540, 110)
$headerPanel.BackColor = $Theme.Panel
$form.Controls.Add($headerPanel)

$picLogo = New-Object System.Windows.Forms.PictureBox
$picLogo.Location = New-Object System.Drawing.Point(15, 10)
$picLogo.Size = New-Object System.Drawing.Size(90, 90)
$picLogo.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$picLogo.BackColor = [System.Drawing.Color]::Transparent
$logoPath = Join-Path $PSScriptRoot "assets\rapidapter_96.png"
if (Test-Path $logoPath) { $picLogo.Image = [System.Drawing.Image]::FromFile($logoPath) }
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
$cmbAdapter.Location = New-Object System.Drawing.Point(100, 122)
$cmbAdapter.Size = New-Object System.Drawing.Size(400, 30)
$cmbAdapter.Font = $font
$cmbAdapter.BackColor = $Theme.Panel
$cmbAdapter.ForeColor = $Theme.Text
$form.Controls.Add($cmbAdapter)

function Refresh-Adapters {
    $cmbAdapter.Items.Clear()
    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
                Where-Object { $_.Status -ne "Disabled" } |
                Sort-Object Status, Name
    foreach ($a in $adapters) { $cmbAdapter.Items.Add($a.Name) | Out-Null }
    if ($cmbAdapter.Items.Count -gt 0) { $cmbAdapter.SelectedIndex = 0 }
}
Refresh-Adapters

# ---- Control helpers ----
function New-Button($text, $x, $y, $w = 490, $h = 38) {
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
    $b.Add_MouseEnter({ param($s, $e) $s.BackColor = $Theme.ButtonHover })
    $b.Add_MouseLeave({ param($s, $e) $s.BackColor = $Theme.Button })
    return $b
}

function New-Separator($y) {
    $s = New-Object System.Windows.Forms.Panel
    $s.Location = New-Object System.Drawing.Point(15, $y)
    $s.Size = New-Object System.Drawing.Size(490, 1)
    $s.BackColor = $Theme.Border
    return $s
}

# ---- DHCP ----
$btnDHCP = New-Button "DHCP - Get IP Automatically" 15 160
$form.Controls.Add($btnDHCP)
$form.Controls.Add((New-Separator 206))

# ---- Preset section label ----
$lblPresets = New-Object System.Windows.Forms.Label
$lblPresets.Text = "PRESETS"
$lblPresets.Location = New-Object System.Drawing.Point(15, 214)
$lblPresets.AutoSize = $true
$lblPresets.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
$lblPresets.ForeColor = $Theme.SubtleText
$form.Controls.Add($lblPresets)

# ---- Preset ListBox ----
$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = New-Object System.Drawing.Point(15, 232)
$listBox.Size = New-Object System.Drawing.Size(490, 148)
$listBox.Font = $font
$listBox.BackColor = $Theme.Panel
$listBox.ForeColor = $Theme.Text
$listBox.BorderStyle = 'FixedSingle'
$listBox.SelectionMode = 'One'
$listBox.IntegralHeight = $false
$form.Controls.Add($listBox)

# ---- Preset management row: Add | Edit | Remove ----
$btnAdd    = New-Button "+ Add"  15  388  158 30
$btnEdit   = New-Button "Edit"  179  388  158 30
$btnRemove = New-Button "Remove" 343  388  162 30
foreach ($b in @($btnAdd, $btnEdit, $btnRemove)) { $b.Font = $fontSm }
$form.Controls.AddRange(@($btnAdd, $btnEdit, $btnRemove))

# ---- Apply preset button (accented) ----
$btnApply = New-Object System.Windows.Forms.Button
$btnApply.Text = "Apply Preset"
$btnApply.Location = New-Object System.Drawing.Point(15, 426)
$btnApply.Size = New-Object System.Drawing.Size(490, 38)
$btnApply.Font = $font
$btnApply.FlatStyle = 'Flat'
$btnApply.UseVisualStyleBackColor = $false
$btnApply.BackColor = $Theme.AccentDark
$btnApply.ForeColor = $Theme.Text
$btnApply.FlatAppearance.BorderColor = $Theme.Accent
$btnApply.FlatAppearance.BorderSize = 1
$btnApply.Add_MouseEnter({ param($s, $e) $s.BackColor = $Theme.AccentHover })
$btnApply.Add_MouseLeave({ param($s, $e) $s.BackColor = $Theme.AccentDark })
$form.Controls.Add($btnApply)

$form.Controls.Add((New-Separator 472))

# ---- Manual button ----
$btnManual = New-Button "Set Manually" 15 480
$form.Controls.Add($btnManual)

# ---- Footer ----
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

# ---- Preset list population ----
$script:Presets = @()

function Update-PresetList {
    $listBox.Items.Clear()
    foreach ($p in $script:Presets) {
        $label = $p.name
        if ($p.ipv4 -and $p.mask) { $label += "  -  $($p.ipv4) / $($p.mask)" }
        if ($p.gw)  { $label += "  GW: $($p.gw)" }
        if ($p.dns) { $label += "  DNS: $($p.dns)" }
        $listBox.Items.Add($label) | Out-Null
    }
}

# ---- Field-row helper for dialogs ----
function Add-FieldRow($container, $y, $labelText, $hint = "") {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $labelText
    $lbl.Location = New-Object System.Drawing.Point(15, ($y + 3))
    $lbl.Size = New-Object System.Drawing.Size(120, 22)
    $lbl.Font = $font
    $container.Controls.Add($lbl)

    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(140, $y)
    $tb.Size = New-Object System.Drawing.Size(255, 28)
    $tb.Font = $font
    $tb.BackColor = $Theme.Panel
    $tb.ForeColor = $Theme.Text
    if ($hint) { try { $tb.PlaceholderText = $hint } catch {} }
    $container.Controls.Add($tb)
    return $tb
}

# ---- Preset add/edit dialog ----
function Show-PresetDialog([PSCustomObject]$existing = $null) {
    $isEdit = $null -ne $existing

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = if ($isEdit) { "Edit Preset" } else { "Add Preset" }
    $dlg.Size = New-Object System.Drawing.Size(420, 318)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.BackColor = $Theme.Back
    $dlg.ForeColor = $Theme.Text

    $fieldDefs = @(
        @{ Label = "Name:";           Key = "name"; Hint = "" },
        @{ Label = "IPv4 Address:";   Key = "ipv4"; Hint = "" },
        @{ Label = "Mask or Prefix:"; Key = "mask"; Hint = "e.g.  24   or   255.255.255.0" },
        @{ Label = "Gateway (opt):";  Key = "gw";   Hint = "" },
        @{ Label = "DNS (opt):";      Key = "dns";  Hint = "" }
    )

    $inputs = @{}
    $y = 18
    foreach ($f in $fieldDefs) {
        $tb = Add-FieldRow $dlg $y $f.Label $f.Hint
        if ($isEdit) {
            $val = $existing.($f.Key)
            if ($val) { $tb.Text = $val }
        }
        $inputs[$f.Key] = $tb
        $y += 42
    }

    $btnSave = New-Object System.Windows.Forms.Button
    $btnSave.Text = "Save"
    $btnSave.Location = New-Object System.Drawing.Point(140, ($y + 4))
    $btnSave.Size = New-Object System.Drawing.Size(100, 34)
    $btnSave.Font = $font
    $dlg.Controls.Add($btnSave)
    $dlg.AcceptButton = $btnSave

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = "Cancel"
    $btnCancel.Location = New-Object System.Drawing.Point(248, ($y + 4))
    $btnCancel.Size = New-Object System.Drawing.Size(100, 34)
    $btnCancel.Font = $font
    $btnCancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($btnCancel)
    $dlg.CancelButton = $btnCancel

    $script:DialogResult = $null
    $btnSave.Add_Click({
        try {
            $name = $inputs["name"].Text.Trim()
            if ([string]::IsNullOrWhiteSpace($name)) { throw "Name is required." }

            $ipv4 = $inputs["ipv4"].Text.Trim()
            if ([string]::IsNullOrWhiteSpace($ipv4)) { throw "IPv4 address is required." }

            $maskRaw = $inputs["mask"].Text.Trim()
            if ([string]::IsNullOrWhiteSpace($maskRaw)) { throw "Mask or prefix is required." }
            if ($maskRaw -match '^\d+$') {
                $pfx = [int]$maskRaw
                if ($pfx -lt 1 -or $pfx -gt 32) { throw "Prefix length must be 1-32." }
            } else {
                MaskToPrefix $maskRaw | Out-Null   # validates; throws on bad input
            }

            $gw  = $inputs["gw"].Text.Trim()
            $dns = $inputs["dns"].Text.Trim()

            $script:DialogResult = [PSCustomObject]@{
                name = $name
                ipv4 = $ipv4
                mask = $maskRaw
                gw   = if ($gw)  { $gw }  else { $null }
                dns  = if ($dns) { $dns } else { $null }
            }
            $dlg.Close()
        } catch {
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Validation Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
        }
    })

    $dlg.ShowDialog($form) | Out-Null
    return $script:DialogResult
}

# ---- Manual IP dialog ----
function Show-ManualForm([string]$iface) {
    $mf = New-Object System.Windows.Forms.Form
    $mf.Text = "Set Manually"
    $mf.Size = New-Object System.Drawing.Size(420, 276)
    $mf.StartPosition = "CenterParent"
    $mf.FormBorderStyle = "FixedDialog"
    $mf.MaximizeBox = $false
    $mf.BackColor = $Theme.Back
    $mf.ForeColor = $Theme.Text

    $rowDefs = @(
        @{ Label = "IPv4 Address:";   Key = "ip";   Hint = "" },
        @{ Label = "Mask or Prefix:"; Key = "mask"; Hint = "e.g.  24   or   255.255.255.0" },
        @{ Label = "Gateway (opt):";  Key = "gw";   Hint = "" },
        @{ Label = "DNS (opt):";      Key = "dns";  Hint = "" }
    )
    $boxes = @{}
    $y = 18
    foreach ($r in $rowDefs) {
        $boxes[$r.Key] = Add-FieldRow $mf $y $r.Label $r.Hint
        $y += 42
    }

    $btnApplyM = New-Object System.Windows.Forms.Button
    $btnApplyM.Text = "Apply"
    $btnApplyM.Location = New-Object System.Drawing.Point(140, ($y + 4))
    $btnApplyM.Size = New-Object System.Drawing.Size(100, 34)
    $btnApplyM.Font = $font
    $mf.Controls.Add($btnApplyM)
    $mf.AcceptButton = $btnApplyM

    $btnCancelM = New-Object System.Windows.Forms.Button
    $btnCancelM.Text = "Cancel"
    $btnCancelM.Location = New-Object System.Drawing.Point(248, ($y + 4))
    $btnCancelM.Size = New-Object System.Drawing.Size(100, 34)
    $btnCancelM.Font = $font
    $btnCancelM.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $mf.Controls.Add($btnCancelM)
    $mf.CancelButton = $btnCancelM

    $btnApplyM.Add_Click({
        try {
            $ip      = $boxes["ip"].Text.Trim()
            $maskRaw = $boxes["mask"].Text.Trim()
            $gw      = $boxes["gw"].Text.Trim()
            $dns     = $boxes["dns"].Text.Trim()

            if ([string]::IsNullOrWhiteSpace($ip))      { throw "IPv4 address is required." }
            if ([string]::IsNullOrWhiteSpace($maskRaw)) { throw "Mask or prefix is required." }

            $prefix = if ($maskRaw -match '^\d+$') { [int]$maskRaw } else { MaskToPrefix $maskRaw }
            if ($prefix -lt 1 -or $prefix -gt 32) { throw "Prefix length must be 1-32." }

            Set-StaticIPv4 -iface $iface -ip $ip -prefix $prefix `
                -gateway (if ($gw)  { $gw }  else { $null }) `
                -dns     (if ($dns) { $dns } else { $null })
            Show-Toast "Set $iface to $ip/$prefix." "Manual Applied"
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

# ---- Event handlers ----
$btnDHCP.Add_Click({
    $iface = $cmbAdapter.SelectedItem
    if (-not $iface) { return }
    try { Set-DHCP $iface; Show-Toast "Set $iface to DHCP (IP + DNS automatic)." }
    catch { Show-Toast $_.Exception.Message "Error" }
})

$btnApply.Add_Click({
    $iface = $cmbAdapter.SelectedItem
    if (-not $iface) { return }
    $idx = $listBox.SelectedIndex
    if ($idx -lt 0) { Show-Toast "Select a preset first." "No Selection"; return }
    $p = $script:Presets[$idx]
    try {
        $prefix = if ($p.mask -match '^\d+$') { [int]$p.mask } else { MaskToPrefix $p.mask }
        Set-StaticIPv4 -iface $iface -ip $p.ipv4 -prefix $prefix -gateway $p.gw -dns $p.dns
        $msg = "Applied '$($p.name)' to $iface`n$($p.ipv4) / $($p.mask)"
        if ($p.gw)  { $msg += "`nGateway: $($p.gw)" }
        if ($p.dns) { $msg += "`nDNS: $($p.dns)" }
        Show-Toast $msg
    } catch { Show-Toast $_.Exception.Message "Error" }
})

$btnAdd.Add_Click({
    $result = Show-PresetDialog
    if ($result) {
        $script:Presets += $result
        Save-Presets $script:Presets
        Update-PresetList
        $listBox.SelectedIndex = $listBox.Items.Count - 1
    }
})

$btnEdit.Add_Click({
    $idx = $listBox.SelectedIndex
    if ($idx -lt 0) { return }
    $result = Show-PresetDialog $script:Presets[$idx]
    if ($result) {
        $script:Presets[$idx] = $result
        Save-Presets $script:Presets
        Update-PresetList
        $listBox.SelectedIndex = $idx
    }
})

$btnRemove.Add_Click({
    $idx = $listBox.SelectedIndex
    if ($idx -lt 0) { return }
    $name = $script:Presets[$idx].name
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Remove preset '$name'?",
        "Confirm",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        $newPresets = for ($i = 0; $i -lt $script:Presets.Count; $i++) {
            if ($i -ne $idx) { $script:Presets[$i] }
        }
        $script:Presets = @($newPresets)
        Save-Presets $script:Presets
        Update-PresetList
    }
})

$btnManual.Add_Click({
    $iface = $cmbAdapter.SelectedItem
    if (-not $iface) { return }
    Show-ManualForm $iface
})

# ---- Init ----
$script:Presets = Import-Presets
Update-PresetList

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
