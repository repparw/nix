let
  tasksOrgPackage = builtins.fetchurl {
    url = "https://raw.githubusercontent.com/NixOS/nixpkgs/68e19592a6d35b03cb050e499d051cff6f8c9539/pkgs/by-name/ta/tasks-org/package.nix";
    sha256 = "sha256-ROHXY5AJiH9B1iarpvCKinvIpAr4HuXXdIcjIwnHq1I=";
  };
in
final: final.callPackage tasksOrgPackage { }
