let
  repparw-alpha = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPFzKXBKbNZ+jr06UNKj0MHIzYw54CMP6suD8iTd7CxH";
  users = [repparw-alpha];

  alpha = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIrytCarAMw1Q2QfgBQd1jgtWsLdetbFXepFEcxwKOBI";
  systems = [
    alpha
  ];
in {
  "github.age".publicKeys = [
    repparw-alpha
    alpha
  ];
  "vikunja.age".publicKeys = [
    repparw-alpha
    alpha
  ];
}
