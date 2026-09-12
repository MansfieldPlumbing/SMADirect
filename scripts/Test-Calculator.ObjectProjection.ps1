$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent;$env:DP_SKIP_START='1';. (Join-Path $root 'Conformance\Calculator.ps1');Import-Module (Join-Path $root 'Apps\Calculator.ObjectProjection.psm1') -Force
$state=[CalculatorState]::new();$before=Export-CalculatorObjectSnapshot -State $state -Buttons $script:Buttons -Epoch 1
$hostedInvoker = (Get-Item -LiteralPath function:Invoke-CalculatorLogic).ScriptBlock
Invoke-CalculatorProjectedButton -State $state -Buttons $script:Buttons -TargetObjectId 104 -HostedInvoker $hostedInvoker # label 7
$after=Export-CalculatorObjectSnapshot -State $state -Buttons $script:Buttons -Epoch 2
if($state.DisplayValue -ne '7'){throw 'Hosted capability did not invoke original Calculator function.'};if($before.ObjectCount -ne $after.ObjectCount -or $after.RootObjectId -ne 1){throw 'Snapshot identity topology changed.'}
[pscustomobject][ordered]@{test='Calculator object graph snapshot and hosted button capability';pass=$true;producer='Authentic SMA-loaded unchanged Calculator.ps1';schema=$after.Schema;beforeObjects=$before.ObjectCount;afterObjects=$after.ObjectCount;rootObjectId=$after.RootObjectId;buttonObjectId=104;beforeDisplay='0';afterDisplay=$state.DisplayValue;hostedOpaqueGaps=$after.HostedOpaqueGaps;verdict='PASS: producer-owned object identity and hosted invocation were preserved; transport/native replica remains unimplemented.'}
