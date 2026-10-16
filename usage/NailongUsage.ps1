param(
    [string]$Directory = $PSScriptRoot,
    [switch]$Preview,
    [switch]$MotionTest,
    [int]$TestExitSeconds = 0,
    [string]$PreviewImagePath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms, UIAutomationClient, UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NailongOverlayLayer {
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int height, uint flags);
    public static void RaiseWithoutActivation(IntPtr h) {
        if (h != IntPtr.Zero) SetWindowPos(h, new IntPtr(-1), 0, 0, 0, 0, 0x13);
    }
}
'@
. (Join-Path $Directory 'Usage.Core.ps1')

$createdNew = $false
$mutexName = if ($Preview) { 'Local\NaifrogUsagePreview' } else { 'Local\NaifrogUsageReminder' }
$mutex = [Threading.Mutex]::new($true, $mutexName, [ref]$createdNew)
if (-not $createdNew) { $mutex.Dispose(); exit 0 }
$settings = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $Directory 'settings.json') | ConvertFrom-Json
$refreshSeconds = [Math]::Max(15, [int]$settings.refreshSeconds)
$autoHideSeconds = [Math]::Max(5, [int]$settings.autoHideSeconds)
$statePath = Join-Path $Directory 'alert-state.json'
$script:alertState = $null
if (Test-Path -LiteralPath $statePath) {
    try {
        $loadedState = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        if ($loadedState.PSObject.Properties['WeekStart'] -and $loadedState.PSObject.Properties['Notified']) {
            $script:alertState = $loadedState
        }
    } catch { }
}

[xml]$buttonXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Width="100" Height="32" WindowStyle="None" ResizeMode="NoResize"
        AllowsTransparency="True" Background="Transparent" Topmost="True"
        ShowInTaskbar="False" ShowActivated="False" Title="奶蛙用量入口">
  <Border Background="#FFF7CC" BorderBrush="#E7B733" BorderThickness="1" CornerRadius="16">
    <Grid Margin="3,2">
      <Grid.ColumnDefinitions><ColumnDefinition Width="64"/><ColumnDefinition Width="4"/><ColumnDefinition Width="26"/></Grid.ColumnDefinitions>
    <Button Name="UsageButton" Content="用量" Background="#FFF7CC" BorderThickness="0"
            Foreground="#604514" FontSize="12" FontFamily="Microsoft YaHei UI"
            HorizontalContentAlignment="Center" VerticalContentAlignment="Center" FocusVisualStyle="{x:Null}"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Cursor="Hand" ToolTip="点击查看用量，再点一次收起" AutomationProperties.Name="查看奶蛙用量">
      <Button.Resources>
        <SolidColorBrush x:Key="HoverBackground" Color="#FFED99"/>
        <SolidColorBrush x:Key="PressedBackground" Color="#FFE277"/>
      </Button.Resources>
    </Button>
    <Button Name="ActivityButton" Grid.Column="2" Content="≡" Foreground="#EAF4FC" FontSize="12"
            FontFamily="Microsoft YaHei UI" Background="#315A77" BorderBrush="#6689A4" BorderThickness="1"
            HorizontalContentAlignment="Center" VerticalContentAlignment="Center" FocusVisualStyle="{x:Null}"
            xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
            Cursor="Hand" ToolTip="查看桌宠活动" AutomationProperties.Name="查看桌宠活动">
      <Button.Resources>
        <SolidColorBrush x:Key="HoverBackground" Color="#467899"/>
        <SolidColorBrush x:Key="PressedBackground" Color="#25465F"/>
      </Button.Resources>
    </Button>
    </Grid>
  </Border>
</Window>
'@
[xml]$bubbleXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Width="328" Height="270" WindowStyle="None" ResizeMode="NoResize"
        AllowsTransparency="True" Background="Transparent" Topmost="True"
        ShowInTaskbar="False" ShowActivated="False" Title="奶蛙用量气泡">
  <Grid Margin="2">
    <Border Background="#FFFCED" BorderBrush="#E7B733" BorderThickness="1.5" CornerRadius="18" Padding="18,13,18,15" Margin="0,0,0,10">
      <StackPanel TextElement.FontFamily="Microsoft YaHei UI" TextElement.Foreground="#604514">
        <DockPanel LastChildFill="True">
          <Button Name="CloseButton" DockPanel.Dock="Right" Content="×" FontSize="20" Width="24" Height="25"
                  Background="Transparent" BorderThickness="0" Foreground="#806839" Cursor="Hand"
                  AutomationProperties.Name="关闭用量气泡"/>
          <TextBlock Text="奶蛙的用量小账本" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center"/>
        </DockPanel>
        <TextBlock Name="AlertText" Text="本周期额度" FontSize="11" Foreground="#9A7425" Margin="0,5,0,9"/>
        <Grid>
          <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition/></Grid.ColumnDefinitions>
          <StackPanel><TextBlock Text="本周期已用" FontSize="11" Foreground="#88744A"/>
            <TextBlock Name="UsedText" Text="—" TextTrimming="CharacterEllipsis" FontSize="21" FontWeight="SemiBold" Margin="0,3,0,0"/></StackPanel>
          <StackPanel Grid.Column="1"><TextBlock Text="当前可用" FontSize="11" Foreground="#88744A"/>
            <TextBlock Name="AvailableText" Text="—" TextTrimming="CharacterEllipsis" FontSize="21" FontWeight="SemiBold" Margin="0,3,0,0"/></StackPanel>
        </Grid>
        <ProgressBar Name="RemainingBar" Height="6" Minimum="0" Maximum="100" Value="0"
                     Foreground="#74A862" Background="#EDE5CD" BorderThickness="0" Margin="0,10,0,7"/>
        <TextBlock Name="PercentText" Text="正在查询额度…" FontSize="11" Foreground="#88744A"/>
        <Border Background="#F6EFD8" CornerRadius="8" Padding="9,7" Margin="0,10,0,0">
          <StackPanel><TextBlock Name="ReserveText" Text="储备余额：—" FontSize="12"/>
            <TextBlock Name="ReserveDetailText" Text="未启用储备不计入当前可用" FontSize="10" Foreground="#88744A" Margin="0,3,0,0"/></StackPanel>
        </Border>
        <DockPanel Margin="0,8,0,0" LastChildFill="True">
          <Button Name="RefreshButton" Content="刷新" DockPanel.Dock="Right" Background="Transparent"
                  BorderThickness="0" Foreground="#9A7425" Padding="6,2" Cursor="Hand" FontSize="11"/>
          <TextBlock Name="StatusText" Text="正在连接…" FontSize="10" Foreground="#88744A" VerticalAlignment="Center" TextWrapping="Wrap"/>
        </DockPanel>
      </StackPanel>
    </Border>
    <Polygon Points="244,249 256,260 267,249" Fill="#FFFCED" Stroke="#E7B733" StrokeThickness="1.5"/>
    <Line X1="245" Y1="249" X2="266" Y2="249" Stroke="#FFFCED" StrokeThickness="3"/>
  </Grid>
</Window>
'@
# The default Windows Button chrome paints a rectangular hover layer. Draw every
# interaction state through the same rounded border instead.
[xml]$roundedButtonTemplateXaml = @'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
  <Border Name="Surface" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
          BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="14" SnapsToDevicePixels="True">
    <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}"
                      VerticalAlignment="{TemplateBinding VerticalContentAlignment}" RecognizesAccessKey="True"/>
  </Border>
  <ControlTemplate.Triggers>
    <Trigger Property="IsMouseOver" Value="True">
      <Setter TargetName="Surface" Property="Background" Value="{DynamicResource HoverBackground}"/>
    </Trigger>
    <Trigger Property="IsPressed" Value="True">
      <Setter TargetName="Surface" Property="Background" Value="{DynamicResource PressedBackground}"/>
    </Trigger>
    <Trigger Property="IsEnabled" Value="False">
      <Setter TargetName="Surface" Property="Opacity" Value="0.5"/>
    </Trigger>
  </ControlTemplate.Triggers>
</ControlTemplate>
'@
function Read-NailongWindow([xml]$Xaml) {
    $reader = [Xml.XmlNodeReader]::new($Xaml)
    try { [Windows.Markup.XamlReader]::Load($reader) } finally { $reader.Close() }
}
$script:entryWindow = Read-NailongWindow $buttonXaml
$script:bubbleWindow = Read-NailongWindow $bubbleXaml
$script:activityButton = $entryWindow.FindName('ActivityButton')
$roundedButtonTemplate = Read-NailongWindow $roundedButtonTemplateXaml
$entryWindow.FindName('UsageButton').Template = $roundedButtonTemplate
$activityButton.Template = $roundedButtonTemplate
$script:controls = @{}
foreach ($name in @('CloseButton', 'AlertText', 'UsedText', 'AvailableText', 'RemainingBar',
    'PercentText', 'ReserveText', 'ReserveDetailText', 'RefreshButton', 'StatusText')) {
    $script:controls[$name] = $bubbleWindow.FindName($name)
}
$script:snapshot = $null
$script:worker = $null
$script:workerHandle = $null
$script:manualOpen = $false
$script:showUntil = [DateTime]::MinValue
$script:petElement = $null
$script:footButtonElement = $null
$script:locator = $null
$script:locatorHandle = $null
$script:anchor = $null
$script:activityWorker = $null
$script:activityHandle = $null
$script:petVisible = $false
$script:nextLocate = [DateTime]::MinValue
$script:nextRefresh = [DateTime]::MinValue
$script:pendingAlert = $null
$script:failed = $false
$script:unconfigured = $false
$script:stateSaveFailed = $false
$script:stateDirty = $false
$script:nextStateSave = [DateTime]::MinValue
$script:stopwatch = [Diagnostics.Stopwatch]::StartNew()
$script:previewSaved = $false
$script:positionUpdates = 0
$script:positionChanges = 0
$script:lastPosition = ''

function Format-NailongMoney($Value) {
    return ([decimal]$Value).ToString('N2', [Globalization.CultureInfo]::CurrentCulture) + ' ' + [string]$settings.unit
}
function Update-NailongDisplay {
    if ($null -ne $script:snapshot) {
        $s = $script:snapshot
        $controls.UsedText.Text = Format-NailongMoney $s.Used
        $controls.AvailableText.Text = Format-NailongMoney $s.Available
        $controls.UsedText.ToolTip = $controls.UsedText.Text
        $controls.AvailableText.ToolTip = $controls.AvailableText.Text
        $controls.RemainingBar.Value = [Math]::Max(0, [Math]::Min(100, [double]$s.RemainingPercent))
        $controls.PercentText.Text = ('本周期可用比例 {0:F1}%' -f $s.RemainingPercent)
        $controls.ReserveText.Text = '储备余额：' + (Format-NailongMoney $s.Reserve)
        $controls.ReserveDetailText.Text = ('已启用 {0} · 未启用 {1}' -f (Format-NailongMoney $s.ReserveActive), (Format-NailongMoney $s.ReserveInactive))
        $time = ([DateTimeOffset]$s.UpdatedAt).ToLocalTime().ToString('MM-dd HH:mm:ss')
        $controls.StatusText.Text = '更新于 ' + $time
        if ($script:failed) { $controls.StatusText.Text = '连接失败 · 上次 ' + $time }
        elseif ($null -ne $script:worker) { $controls.StatusText.Text += ' · 刷新中' }
        elseif ($script:stateSaveFailed) { $controls.StatusText.Text += ' · 提醒记录未保存' }
        $color = if ($s.Available -le 0) { '#C44937' } elseif ($s.RemainingPercent -le 20) { '#BD7B20' } else { '#74A862' }
        $controls.RemainingBar.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString($color)
        $controls.AvailableText.Foreground = $controls.RemainingBar.Foreground
    }
    else {
        $controls.StatusText.Text = if ($script:unconfigured) { '未接入 · 请按 usage/README.md 配置适配器' } elseif ($script:failed) { '连接失败 · 点击刷新重试' } else { '正在连接…' }
        $controls.PercentText.Text = if ($script:unconfigured) { '尚未配置用量服务' } else { '额度未知' }
    }
    $controls.RefreshButton.IsEnabled = $null -eq $script:worker
}

function Start-NailongRefresh {
    if ($null -ne $script:worker) { return }
    $script:worker = [PowerShell]::Create()
    $null = $script:worker.AddScript({
        param($usageDirectory)
        $ErrorActionPreference = 'Stop'
        try {
            . (Join-Path $usageDirectory 'Usage.Core.ps1')
            [pscustomobject]@{ Success = $true; Unconfigured = $false; Snapshot = (Get-NailongUsage -Directory $usageDirectory) }
        } catch {
            # Never propagate provider errors, which may contain credentials.
            [pscustomobject]@{ Success = $false; Unconfigured = ($_.Exception.Message -eq 'NAIFROG_NOT_CONFIGURED'); Snapshot = $null }
        }
    }.ToString()).AddArgument($Directory)
    $script:workerHandle = $script:worker.BeginInvoke()
    Update-NailongDisplay
}

function Complete-NailongRefresh {
    if ($null -eq $script:worker -or -not $script:workerHandle.IsCompleted) { return }
    $result = $null
    try {
        $items = $script:worker.EndInvoke($script:workerHandle)
        if ($items.Count -gt 0) { $result = $items[$items.Count - 1] }
    } catch { }
    $script:worker.Dispose()
    $script:worker = $null
    $script:workerHandle = $null
    $script:nextRefresh = [DateTime]::UtcNow.AddSeconds($refreshSeconds)
    $script:failed = $null -eq $result -or -not $result.Success
    $script:unconfigured = $null -ne $result -and $result.Unconfigured
    if ($script:unconfigured) { $script:snapshot = $null }
    if (-not $script:failed) {
        $script:snapshot = $result.Snapshot
        # Wait until a visible pet can actually display a reminder before marking it sent.
        $decision = Get-NailongAlertDecision $script:snapshot $script:alertState
        $script:pendingAlert = if ($decision.Show -and -not $Preview) { $decision } else { $null }
    }
    else { $script:pendingAlert = $null }
    Update-NailongDisplay
}

function Find-NailongPet {
    $script:footButtonElement = $null
    $configPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\config.toml'
    if (-not (Test-Path -LiteralPath $configPath)) { return $null }
    $selected = Get-Content -Raw -Encoding UTF8 -LiteralPath $configPath
    if ($selected -notmatch '(?m)^\s*selected-avatar-id\s*=\s*["'']custom:naifrog["'']\s*$') { return $null }
    $root = [Windows.Automation.AutomationElement]::RootElement
    $windows = $root.FindAll([Windows.Automation.TreeScope]::Children, [Windows.Automation.Condition]::TrueCondition)
    $imageCondition = [Windows.Automation.PropertyCondition]::new(
        [Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Image)
    foreach ($window in $windows) {
        try {
            if ($window.Current.ClassName -ne 'Chrome_WidgetWin_1' -or
                $window.Current.IsOffscreen) { continue }
            $process = Get-Process -Id $window.Current.ProcessId -ErrorAction SilentlyContinue
            # New desktop builds host the same codex-avatar element inside ChatGPT.
            # Its host window may span a full monitor; do not infer pet visibility from window size.
            if ($null -eq $process -or $process.ProcessName -notin @('codex', 'ChatGPT')) { continue }
            foreach ($image in $window.FindAll([Windows.Automation.TreeScope]::Descendants, $imageCondition)) {
                $rect = $image.Current.BoundingRectangle
                if ($image.Current.ClassName -like 'codex-avatar-button*' -and
                    -not $image.Current.IsOffscreen -and $rect.Width -ge 40 -and $rect.Height -ge 40) {
                    $buttonCondition = [Windows.Automation.PropertyCondition]::new(
                        [Windows.Automation.AutomationElement]::ControlTypeProperty, [Windows.Automation.ControlType]::Button)
                    foreach ($button in $window.FindAll([Windows.Automation.TreeScope]::Descendants, $buttonCondition)) {
                        $buttonRect = $button.Current.BoundingRectangle
                        if (-not $button.Current.IsOffscreen -and $buttonRect.Width -ge 16 -and
                            $buttonRect.Width -le 60 -and $buttonRect.Height -le 40 -and
                            $buttonRect.Left -ge $rect.Left - 40 -and $buttonRect.Right -le $rect.Right + 40 -and
                            $buttonRect.Top -ge $rect.Bottom - 10 -and $buttonRect.Bottom -le $rect.Bottom + 60) {
                            $script:footButtonElement = $button
                            break
                        }
                    }
                    $hostRect = $window.Current.BoundingRectangle
                    $foot = if ($null -ne $script:footButtonElement) { $script:footButtonElement.Current.BoundingRectangle } else { $null }
                    return [pscustomobject]@{
                        ImageElement = $image
                        Left = $rect.Left; Top = $rect.Top
                        Handle = [long]$window.Current.NativeWindowHandle
                        X = $rect.Left - $hostRect.Left; Y = $rect.Top - $hostRect.Top
                        Width = $rect.Width; Height = $rect.Height
                        FootY = if ($null -ne $foot) { $foot.Top - $rect.Top + [Math]::Max($foot.Width, $foot.Height) / 2 } else { $rect.Height + 16 }
                        ActivityName = if ($null -ne $script:footButtonElement) { $script:footButtonElement.Current.Name } else { '' }
                        ActivityElement = $script:footButtonElement
                    }
                }
            }
        } catch { continue }
    }
    return $null
}

function Update-NailongLocator {
    if ($null -ne $script:locator -and $script:locatorHandle.IsCompleted) {
        try {
            $results = $script:locator.EndInvoke($script:locatorHandle)
            $script:anchor = if ($results.Count -gt 0) { $results[$results.Count - 1] } else { $null }
        } catch { $script:anchor = $null }
        $script:locator.Dispose(); $script:locator = $null
        $script:nextLocate = [DateTime]::UtcNow.AddMilliseconds(33)
    }
    if ($null -eq $script:locator -and [DateTime]::UtcNow -ge $script:nextLocate) {
        $script:locator = [PowerShell]::Create()
        $null = $script:locator.AddScript({
            param($definition, $cached)
            $ErrorActionPreference = 'Stop'
            if ($null -ne $cached) {
                try {
                    $configPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\config.toml'
                    $configText = Get-Content -Raw -Encoding UTF8 -LiteralPath $configPath
                    if ($configText -notmatch '(?m)^\s*selected-avatar-id\s*=\s*["'']custom:naifrog["'']\s*$') { throw 'Other pet selected.' }
                    $image = $cached.ImageElement
                    $r = $image.Current.BoundingRectangle
                    if ($image.Current.IsOffscreen -or $r.Width -lt 40 -or $r.Height -lt 40) { throw 'Pet hidden.' }
                    $cached.Left = $r.Left; $cached.Top = $r.Top
                    $cached.Width = $r.Width; $cached.Height = $r.Height
                    if ($null -ne $cached.ActivityElement) {
                        $foot = $cached.ActivityElement.Current.BoundingRectangle
                        $cached.FootY = $foot.Top - $r.Top + [Math]::Max($foot.Width, $foot.Height) / 2
                        $cached.ActivityName = $cached.ActivityElement.Current.Name
                    }
                    return $cached
                } catch {}
            }
            . ([scriptblock]::Create('function Find-NailongPet {' + $definition + '}'))
            Find-NailongPet
        }.ToString()).AddArgument(${function:Find-NailongPet}.ToString()).AddArgument($script:anchor)
        $script:locatorHandle = $script:locator.BeginInvoke()
    }
}

function Set-NailongPosition($Rect) {
    $script:positionUpdates++
    $position = $Rect.ToString()
    if ($position -ne $script:lastPosition) {
        $script:positionChanges++
        $script:lastPosition = $position
    }
    # UI Automation reports physical pixels; WPF windows use device-independent units.
    $source = [Windows.PresentationSource]::FromVisual($entryWindow)
    $scaleX = 1.0; $scaleY = 1.0
    if ($null -ne $source -and $null -ne $source.CompositionTarget) {
        $transform = $source.CompositionTarget.TransformFromDevice
        $scaleX = $transform.M11; $scaleY = $transform.M22
    }
    $screen = [Windows.Forms.Screen]::FromPoint([Drawing.Point]::new([int]$Rect.Left, [int]$Rect.Top))
    $area = $screen.WorkingArea
    $left = $area.Left * $scaleX; $top = $area.Top * $scaleY
    $right = $area.Right * $scaleX; $bottom = $area.Bottom * $scaleY
    $petLeft = $Rect.Left * $scaleX; $petTop = $Rect.Top * $scaleY
    $petRight = $Rect.Right * $scaleX
    # One centered opaque row hosts usage on the left and native activity on the right.
    # Both controls move together and the continuous background covers the old badge.
    $buttonLeft = (($petLeft + $petRight) / 2) - $entryWindow.Width / 2
    $buttonTop = $Rect.Bottom * $scaleY + 4
    if ($null -ne $script:anchor) {
                $buttonTop = ($Rect.Top + $script:anchor.FootY) * $scaleY - $entryWindow.Height / 2
                $activityName = $script:anchor.ActivityName
                $activityButton.Content = if ($activityName -match '(\d+)\s*(?:项|activities|activity)') { $Matches[1] } else { '≡' }
                $activityButton.ToolTip = $activityName
    }
    $entryWindow.Left = [Math]::Max($left, [Math]::Min($right - $entryWindow.Width, $buttonLeft))
    $entryWindow.Top = [Math]::Max($top, [Math]::Min($bottom - $entryWindow.Height, $buttonTop))
    # Dragging can bring the native pet's topmost window ahead of ours. Restore the
    # overlay order without activating it or stealing keyboard focus.
    [NailongOverlayLayer]::RaiseWithoutActivation([Windows.Interop.WindowInteropHelper]::new($entryWindow).Handle)
    $bubbleWindow.Left = [Math]::Max($left, [Math]::Min($right - $bubbleWindow.Width, $petRight - 260))
    $bubbleTop = $petTop - $bubbleWindow.Height - 4
    if ($bubbleTop -lt $top) { $bubbleTop = $Rect.Bottom * $scaleY + 6 }
    $bubbleWindow.Top = [Math]::Max($top, [Math]::Min($bottom - $bubbleWindow.Height, $bubbleTop))
    if ($bubbleWindow.IsVisible) {
        [NailongOverlayLayer]::RaiseWithoutActivation([Windows.Interop.WindowInteropHelper]::new($bubbleWindow).Handle)
    }
}

function Update-NailongPet {
    $script:petVisible = $false
    if ($Preview) {
        $area = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $offset = if ($MotionTest) { 100 * [Math]::Sin($script:stopwatch.Elapsed.TotalSeconds * 3) } else { 0 }
        $verticalOffset = if ($MotionTest) { 100 * [Math]::Cos($script:stopwatch.Elapsed.TotalSeconds * 3) } else { 0 }
        $rect = [Windows.Rect]::new($area.Right - 340 + $offset, $area.Bottom - 300 + $verticalOffset, 120, 140)
        $script:petVisible = $true
    }
    else {
        Update-NailongLocator
        if ($null -ne $script:anchor) {
            $hostBounds = [NailongOverlayLayer+Rect]::new()
            $handle = [IntPtr]$script:anchor.Handle
            if ([NailongOverlayLayer]::IsWindowVisible($handle) -and [NailongOverlayLayer]::GetWindowRect($handle, [ref]$hostBounds)) {
                $rect = [Windows.Rect]::new($script:anchor.Left, $script:anchor.Top, $script:anchor.Width, $script:anchor.Height)
                $script:petVisible = $true
                $script:footButtonElement = $script:anchor.ActivityElement
            }
        }
    }
    if ($script:petVisible) {
        if (-not $entryWindow.IsVisible) { $entryWindow.Show() }
        Set-NailongPosition $rect
        $activityButton.IsEnabled = $null -ne $script:footButtonElement
    }
    else {
        $entryWindow.Hide()
        $bubbleWindow.Hide()
    }
}

function Save-NailongAlertState {
    if ($Preview -or -not $script:stateDirty -or [DateTime]::UtcNow -lt $script:nextStateSave) { return }
    try {
        $tempState = $statePath + '.tmp'
        $script:alertState | ConvertTo-Json -Depth 3 | Set-Content -Encoding UTF8 -LiteralPath $tempState -ErrorAction Stop
        Move-Item -LiteralPath $tempState -Destination $statePath -Force -ErrorAction Stop
        $script:stateDirty = $false
        $script:stateSaveFailed = $false
    } catch {
        # Keep the in-memory deduplication, but retry persistence even while hidden/offline.
        $script:stateSaveFailed = $true
        $script:nextStateSave = [DateTime]::UtcNow.AddSeconds(5)
    }
    Update-NailongDisplay
}

function Show-NailongPendingAlert {
    if (-not $script:petVisible -or $script:failed -or $null -eq $script:pendingAlert) { return }
    $decision = $script:pendingAlert
    $controls.AlertText.Text = if ($decision.Level -eq 0) { '额度已耗尽，需要补充额度啦' } else { '可用额度降至 ' + $decision.Level + '% 以内' }
    if (-not $script:manualOpen) { $script:showUntil = [DateTime]::UtcNow.AddSeconds($autoHideSeconds) }
    $bubbleWindow.Show()
    $script:alertState = $decision.State
    $script:pendingAlert = $null
    $script:stateDirty = $true
    $script:nextStateSave = [DateTime]::MinValue
    Save-NailongAlertState
    Update-NailongDisplay
}

$entryWindow.FindName('UsageButton').Add_Click({
    if ($bubbleWindow.IsVisible) {
        $script:manualOpen = $false
        $script:showUntil = [DateTime]::MinValue
        $bubbleWindow.Hide()
        return
    }
    $script:manualOpen = $true
    $controls.AlertText.Text = '本周期额度 · 未启用储备另列'
    $bubbleWindow.Show()
    Start-NailongRefresh
})
$activityButton.Add_Click({
    try {
        if ($null -ne $script:footButtonElement) {
            if ($null -ne $script:activityWorker) { return }
            $script:activityWorker = [PowerShell]::Create()
            $null = $script:activityWorker.AddScript('param($element) try { $element.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke() } catch {}').AddArgument($script:footButtonElement)
            $script:activityHandle = $script:activityWorker.BeginInvoke()
        }
    } catch {
        $script:footButtonElement = $null
        $script:nextLocate = [DateTime]::MinValue
    }
})
$controls.RefreshButton.Add_Click({ Start-NailongRefresh })
$controls.CloseButton.Add_Click({
    $script:manualOpen = $false
    $script:showUntil = [DateTime]::MinValue
    $bubbleWindow.Hide()
})
$entryWindow.Add_Closing({ $script:frame.Continue = $false })

$script:frame = [Windows.Threading.DispatcherFrame]::new()
$timer = [Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds(33)
$timer.Add_Tick({
    try {
        $now = [DateTime]::UtcNow
        if ($null -ne $script:activityWorker -and $script:activityHandle.IsCompleted) {
            try { $null = $script:activityWorker.EndInvoke($script:activityHandle) } catch {}
            $script:activityWorker.Dispose(); $script:activityWorker = $null
        }
        Complete-NailongRefresh
        if ($now -ge $script:nextRefresh -and $null -eq $script:worker) { Start-NailongRefresh }
        Update-NailongPet
        Show-NailongPendingAlert
        Save-NailongAlertState
        if ($script:petVisible -and ($script:manualOpen -or $now -lt $script:showUntil)) {
            if (-not $bubbleWindow.IsVisible) { $bubbleWindow.Show() }
        }
        elseif ($bubbleWindow.IsVisible) { $bubbleWindow.Hide() }
        if ($Preview -and -not $script:previewSaved -and $null -ne $script:snapshot -and $PreviewImagePath) {
            $bubbleWindow.UpdateLayout()
            $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(328, 270, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
            $bitmap.Render($bubbleWindow.Content)
            $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
            $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
            $stream = [IO.File]::Create($PreviewImagePath)
            try { $encoder.Save($stream) } finally { $stream.Dispose() }
            $script:previewSaved = $true
        }
        if ($TestExitSeconds -gt 0 -and $script:stopwatch.Elapsed.TotalSeconds -ge $TestExitSeconds) {
            $script:frame.Continue = $false
        }
    } catch {
        # Avoid repeated UI errors and never print exceptions containing user configuration.
        $controls.StatusText.Text = '显示暂时不可用 · 正在重试'
        $script:nextLocate = [DateTime]::UtcNow.AddSeconds(3)
        if ($TestExitSeconds -gt 0 -and $script:stopwatch.Elapsed.TotalSeconds -ge $TestExitSeconds) {
            $script:frame.Continue = $false
        }
    }
})
try {
    if ($Preview) { $script:manualOpen = $true }
    $timer.Start()
    [Windows.Threading.Dispatcher]::PushFrame($script:frame)
    if ($TestExitSeconds -gt 0) {
        [pscustomobject]@{ SnapshotLoaded = $null -ne $script:snapshot; ConnectionFailed = $script:failed; Unconfigured = $script:unconfigured;
            PreviewSaved = $script:previewSaved; PetVisible = $script:petVisible;
            PositionUpdates = $script:positionUpdates; PositionChanges = $script:positionChanges } | ConvertTo-Json -Compress | Write-Output
    }
} finally {
    $timer.Stop()
    $script:nextStateSave = [DateTime]::MinValue
    Save-NailongAlertState
    if ($null -ne $script:worker) {
        $script:worker.Stop()
        $script:worker.Dispose()
    }
    if ($null -ne $script:locator) {
        $script:locator.Stop(); $script:locator.Dispose()
    }
    if ($null -ne $script:activityWorker) {
        $script:activityWorker.Stop(); $script:activityWorker.Dispose()
    }
    $bubbleWindow.Close()
    $entryWindow.Close()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
