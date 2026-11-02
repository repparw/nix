# Fleet glossary

Shared language for the managed NixOS fleet. These are domain concepts, not
implementation rules or operating instructions.

## Fleet and configuration

**Fleet**:
The set of hosts managed under one configuration and coordinated update process.
_Avoid_: Cluster

**Host**:
A physical or virtual machine managed as a distinct NixOS system.
_Avoid_: Node, except when referring to a tool's own node concept

**Aspect**:
A reusable capability or policy assigned to a host or user. An aspect may
compose other aspects and need not correspond to a running service.

## Services and access

**Registered service**:
An application or workload with a fleet-wide record of where it runs and
how the fleet treats it operationally.

**Service definition**:
The authoritative facts about a registered service's location, access, and
operational responsibilities.

**Service registry**:
The fleet-wide collection of service definitions.

**Hosting host**:
The host on which a service actually runs, whether directly or in a container.

**Edge**:
A fleet-managed entry point that receives requests for a service and routes
them toward its backend. The edge and hosting host can be different machines.

**Backend**:
The service endpoint to which an edge forwards requests.

## Deployment

**Deployment controller**:
The host responsible for coordinating and serializing fleet update attempts.

**Deployment target**:
A host whose system configuration is activated by the fleet deployment process.
