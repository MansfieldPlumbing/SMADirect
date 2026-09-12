# SMADirect

SMADirect observes authentic `System.Management.Automation` execution and retains the concrete runtime objects, relationships, storage, and callables that PowerShell actually resolves.

The source remains ordinary PowerShell.

```text
.ps1
    ↓
authentic SMA parse / compile / execute
    ↓
live runtime resolution
    ↓
concrete objects / members / callables / storage
    ↓
retained application object graph
    ↓
rematerialization / native realization as required