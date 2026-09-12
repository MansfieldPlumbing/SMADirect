Set-StrictMode -Version Latest

function New-DirectPortStructuralProjection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][uint64] $ProjectionId,
        [Parameter(Mandatory)][uint64] $SourceNodeId,
        [Parameter(Mandatory)][ValidateSet('Type','Property','Field','Method','Constructor','Event','Indexer')][string] $Kind,
        [Parameter(Mandatory)][string] $OwnerIdentity,
        [Parameter(Mandatory)][string] $MemberIdentity,
        [Parameter(Mandatory)][string] $Signature,
        [Parameter(Mandatory)][uint64] $Capability,
        [Parameter(Mandatory)][string] $EvidenceSha256,
        [uint64] $PublicationValue = 0
    )
    if ($ProjectionId -eq 0 -or $Capability -eq 0) { throw 'Projection and capability identities must be nonzero.' }
    if ($EvidenceSha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw 'Projection evidence must be a SHA-256 value.' }
    [pscustomobject][ordered]@{
        PortSchema       = 'DirectPort.StructuralProjection.v1'
        ProjectionId    = $ProjectionId
        SourceNodeId    = $SourceNodeId
        Kind            = $Kind
        OwnerIdentity   = $OwnerIdentity
        MemberIdentity  = $MemberIdentity
        Signature       = $Signature
        Capability      = $Capability
        EvidenceSha256  = $EvidenceSha256.ToUpperInvariant()
        PublicationValue = $PublicationValue
    }
}

function New-DirectPortResolutionCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][uint64] $CandidateId,
        [Parameter(Mandatory)][uint64] $UnresolvedSiteId,
        [Parameter(Mandatory)][uint64] $ProjectionId,
        [Parameter(Mandatory)][ValidateRange(0.0,1.0)][double] $Confidence,
        [Parameter(Mandatory)][string] $Reason,
        [Parameter(Mandatory)][uint64] $EvidenceCapability,
        [uint32] $ObservationCount = 1,
        [uint64] $PublicationValue = 0
    )
    if ($CandidateId -eq 0 -or $UnresolvedSiteId -eq 0 -or $ProjectionId -eq 0 -or $EvidenceCapability -eq 0) {
        throw 'Candidate, site, projection, and evidence identities must be nonzero.'
    }
    [pscustomobject][ordered]@{
        PortSchema        = 'DirectPort.CandidateResolution.v1'
        CandidateId      = $CandidateId
        UnresolvedSiteId = $UnresolvedSiteId
        ProjectionId     = $ProjectionId
        Confidence       = $Confidence
        Reason           = $Reason
        EvidenceCapability = $EvidenceCapability
        ObservationCount = $ObservationCount
        PublicationValue = $PublicationValue
    }
}

function New-DirectPortVerifiedResolution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject] $Candidate,
        [Parameter(Mandatory)][psobject] $Projection,
        [Parameter(Mandatory)][string] $VerificationKind,
        [Parameter(Mandatory)][string] $VerificationSha256,
        [Parameter(Mandatory)][uint64] $VerifierCapability,
        [Parameter(Mandatory)][bool] $ExactMatch,
        [uint64] $PublicationValue = 0
    )
    if ($Candidate.PortSchema -ne 'DirectPort.CandidateResolution.v1') { throw 'Candidate schema is not admitted.' }
    if ($Projection.PortSchema -ne 'DirectPort.StructuralProjection.v1') { throw 'Projection schema is not admitted.' }
    if (!$ExactMatch) { throw 'NO ADMITTED LOWERING: a ranked candidate requires exact verification.' }
    if ($Candidate.ProjectionId -ne $Projection.ProjectionId) { throw 'Candidate and projection identities do not match.' }
    if ($VerificationSha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw 'Verification evidence must be a SHA-256 value.' }
    if ($VerifierCapability -eq 0) { throw 'Verifier capability must be nonzero.' }
    [pscustomobject][ordered]@{
        PortSchema         = 'DirectPort.VerifiedResolution.v1'
        UnresolvedSiteId  = [uint64]$Candidate.UnresolvedSiteId
        ProjectionId      = [uint64]$Projection.ProjectionId
        MemberCapability  = [uint64]$Projection.Capability
        VerificationKind  = $VerificationKind
        VerificationSha256 = $VerificationSha256.ToUpperInvariant()
        VerifierCapability = $VerifierCapability
        PublicationValue  = $PublicationValue
    }
}

function New-DirectPortNativeLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][uint64] $LayoutId,
        [Parameter(Mandatory)][uint64] $ProjectionId,
        [Parameter(Mandatory)][string] $LayoutIdentity,
        [Parameter(Mandatory)][uint32] $LengthOffset,
        [Parameter(Mandatory)][uint32] $CapacityOffset,
        [Parameter(Mandatory)][uint32] $StorageOffset,
        [Parameter(Mandatory)][uint32] $StorageCapacityChars,
        [Parameter(Mandatory)][ValidateSet('Reject','Truncate','Grow')][string] $OverflowBehavior,
        [Parameter(Mandatory)][string] $Encoding,
        [Parameter(Mandatory)][string] $EvidenceSha256,
        [uint64] $PublicationValue = 0
    )
    if ($LayoutId -eq 0 -or $ProjectionId -eq 0 -or $StorageCapacityChars -eq 0) {
        throw 'Layout, projection, and storage-capacity facts must be nonzero.'
    }
    if ($EvidenceSha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw 'Layout evidence must be a SHA-256 value.' }
    [pscustomobject][ordered]@{
        PortSchema          = 'DirectPort.NativeLayout.v1'
        LayoutId           = $LayoutId
        ProjectionId       = $ProjectionId
        LayoutIdentity     = $LayoutIdentity
        LengthOffset       = $LengthOffset
        CapacityOffset     = $CapacityOffset
        StorageOffset      = $StorageOffset
        StorageCapacityChars = $StorageCapacityChars
        OverflowBehavior   = $OverflowBehavior
        Encoding           = $Encoding
        EvidenceSha256     = $EvidenceSha256.ToUpperInvariant()
        PublicationValue   = $PublicationValue
    }
}

function New-DirectPortLoweringBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][uint64] $BindingId,
        [Parameter(Mandatory)][uint64] $SourceNodeId,
        [Parameter(Mandatory)][uint64] $DeclarationNodeId,
        [Parameter(Mandatory)][uint32] $DynamicOrdinal,
        [Parameter(Mandatory)][uint64] $ProjectionId,
        [Parameter(Mandatory)][uint64] $LayoutId,
        [Parameter(Mandatory)][string] $NativeArtifactSha256,
        [Parameter(Mandatory)][bool] $NativeClosureExecuted,
        [Parameter(Mandatory)][bool] $AccessSiteRedirected,
        [string] $SmaBinderKind = '',
        [string] $SmaReceiverType = '',
        [uint32] $MatchingSmaSiteCount = 0,
        [bool] $ReceiverRepresentationRewritten = $false,
        [uint64] $PublicationValue = 0
    )
    if ($BindingId -eq 0 -or $SourceNodeId -eq 0 -or $DeclarationNodeId -eq 0 -or $ProjectionId -eq 0 -or $LayoutId -eq 0) {
        throw 'Binding, access, declaration, projection, and layout identities must be nonzero.'
    }
    if ($NativeArtifactSha256 -notmatch '^[0-9A-Fa-f]{64}$') { throw 'Native artifact evidence must be a SHA-256 value.' }
    if ($AccessSiteRedirected -and (-not $NativeClosureExecuted -or -not $ReceiverRepresentationRewritten)) {
        throw 'NO ADMITTED LOWERING: connected binding requires executed native closure and rewritten receiver representation.'
    }
    [pscustomobject][ordered]@{
        PortSchema           = 'DirectPort.LoweringBinding.v1'
        BindingId           = $BindingId
        SourceNodeId        = $SourceNodeId
        AccessNodeId        = $SourceNodeId
        DeclarationNodeId   = $DeclarationNodeId
        DynamicOrdinal      = $DynamicOrdinal
        ProjectionId        = $ProjectionId
        LayoutId            = $LayoutId
        NativeArtifactSha256 = $NativeArtifactSha256.ToUpperInvariant()
        NativeClosureExecuted = $NativeClosureExecuted
        AccessSiteRedirected = $AccessSiteRedirected
        SmaBinderKind        = $SmaBinderKind
        SmaReceiverType      = $SmaReceiverType
        MatchingSmaSiteCount = $MatchingSmaSiteCount
        ReceiverRepresentationRewritten = $ReceiverRepresentationRewritten
        BindingState        = if ($AccessSiteRedirected) { 'ConnectedLowering' } else { 'ParallelClosure' }
        PublicationValue    = $PublicationValue
    }
}

function ConvertTo-DirectPortProjectionText {
    [CmdletBinding()]
    param([Parameter(Mandatory,ValueFromPipeline)][psobject[]] $InputObject)
    process {
        foreach ($record in $InputObject) {
            if ($record.PortSchema -notin @(
                'DirectPort.StructuralProjection.v1',
                'DirectPort.CandidateResolution.v1',
                'DirectPort.VerifiedResolution.v1',
                'DirectPort.NativeLayout.v1',
                'DirectPort.LoweringBinding.v1')) {
                throw 'Record schema is not a DirectPort resolution-port schema.'
            }
            $record | ConvertTo-Json -Compress -Depth 4
        }
    }
}

Export-ModuleMember -Function @(
    'New-DirectPortStructuralProjection',
    'New-DirectPortResolutionCandidate',
    'New-DirectPortVerifiedResolution',
    'New-DirectPortNativeLayout',
    'New-DirectPortLoweringBinding',
    'ConvertTo-DirectPortProjectionText'
)
