[CmdletBinding()]
param(
    [ValidateSet('offset', 'scale')]
    [string] $Kind = 'offset',

    [int] $Value = 7
)

$offset = [pscustomobject]@{
    Kind = 'offset'
    Operand = 3
}
$offset | Add-Member -MemberType ScriptMethod -Name invoke -Value {
    param([int] $inputValue)
    $inputValue + $this.Operand
}

$scale = [pscustomobject]@{
    Kind = 'scale'
    Operand = 4
}
$scale | Add-Member -MemberType ScriptMethod -Name invoke -Value {
    param([int] $inputValue)
    $inputValue * $this.Operand
}

$population = @{
    offset = $offset
    scale = $scale
}

$selected = $population[$Kind]
$selected.invoke($Value)
