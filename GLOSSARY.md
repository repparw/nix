# Fleet glossary

Shared language for the managed NixOS fleet. Definitions describe domain
concepts, not configuration syntax or operating procedures.

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

**Service**:
An application or system-managed process or task operated on a host. A service
does not need to appear in the fleet's service inventory.

**Service inventory**:
The selected services whose locations, access requirements, or operational
responsibilities are tracked across the fleet.

**Service definition**:
A service inventory entry describing one service's location, access, and
operational responsibilities.

**Edge**:
A fleet-managed entry point that receives requests for a service and routes
them toward its backend. The edge and the machine running the service can differ.

**Backend**:
The service endpoint to which an edge forwards requests.

## Deployment

**Deployment controller**:
The host responsible for coordinating and serializing fleet update attempts.

**Deployment target**:
A host whose system configuration is activated by the fleet deployment process.
