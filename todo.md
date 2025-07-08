# Todo

## High Priority
- Add type checking for NixOS module options
  * Add explicit types for all module options using lib.types
  * Ensure type safety for complex nested configurations
  * Validate enum values and numeric ranges

- Document configuration options in each module
  * Add description field to each mkOption
  * Include example values and use cases
  * Document dependencies between options

- Create central secrets management documentation
  * Document agenix setup and usage
  * List all secret files and their purposes
  * Add instructions for rotating secrets

- Add input validation for service configurations
  * Validate URLs and ports
  * Check file paths exist
  * Ensure required services are enabled

## Medium Priority
- Consolidate duplicate code across similar services
- Add health checks for critical services
- Create backup configuration module
- Add update notifications for services

## Low Priority
- Add development container configuration
- Create module unit tests
- Add system configuration diagrams
- Document network topology

## explore?
- [ ] onfailure autoupgrade notify
- [ ] no sound over DP/HDMI on both monitors