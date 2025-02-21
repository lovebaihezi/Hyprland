{
  self,
  lib,
  inputs,
}: let
  props = builtins.fromJSON (builtins.readFile ../props.json);

  mkDate = longDate: (lib.concatStringsSep "-" [
    (builtins.substring 0 4 longDate)
    (builtins.substring 4 2 longDate)
    (builtins.substring 6 2 longDate)
  ]);

  mkJoinedOverlays = overlays: final: prev:
    lib.foldl' (attrs: overlay: attrs // (overlay final prev)) {} overlays;
in {
  # Contains what a user is most likely to care about:
  # Hyprland itself, XDPH, the Share Picker, and patched Waybar.
  default = mkJoinedOverlays (with self.overlays; [
    hyprland-packages
    hyprland-extras
  ]);

  # Packages for variations of Hyprland, dependencies included.
  hyprland-packages = mkJoinedOverlays [
    # Dependencies
    inputs.hyprland-protocols.overlays.default
    self.overlays.wlroots-hyprland
    self.overlays.udis86
    # Hyprland packages themselves
    (final: prev: {
      hyprland = final.callPackage ./default.nix {
        version = "${props.version}+date=${mkDate (self.lastModifiedDate or "19700101")}_${self.shortRev or "dirty"}";
        wlroots = final.wlroots-hyprland;
        commit = self.rev or "";
        inherit (final) udis86 hyprland-protocols;
      };

      hyprland-unwrapped = final.hyprland.override {wrapRuntimeDeps = false;};
      hyprland-debug = final.hyprland.override {debug = true;};
      hyprland-hidpi = final.hyprland.override {hidpiXWayland = true;};
      hyprland-nvidia = final.hyprland.override {nvidiaPatches = true;};
      hyprland-no-hidpi =
        builtins.trace
        "hyprland-no-hidpi was removed. Please use the default package."
        final.hyprland;
    })
  ];

  # Packages for extra software recommended for usage with Hyprland,
  # including forked or patched packages for compatibility.
  hyprland-extras = mkJoinedOverlays [
    inputs.xdph.overlays.xdg-desktop-portal-hyprland
    inputs.xdph.overlays.hyprland-share-picker
    self.overlays.waybar-hyprland
  ];

  waybar-hyprland = final: prev: {
    waybar-hyprland = prev.waybar.overrideAttrs (old: {
      postPatch = ''
        # use hyprctl to switch workspaces
        sed -i 's/zext_workspace_handle_v1_activate(workspace_handle_);/const std::string command = "hyprctl dispatch workspace " + name_;\n\tsystem(command.c_str());/g' src/modules/wlr/workspace_manager.cpp
      '';
      postFixup = ''
        wrapProgram $out/bin/waybar \
          --suffix PATH : ${lib.makeBinPath [final.hyprland]}
      '';
      mesonFlags = old.mesonFlags ++ ["-Dexperimental=true"];
    });
  };

  udis86 = final: prev: {
    udis86 = final.callPackage ./udis86.nix {};
  };

  # Patched version of wlroots for Hyprland.
  # It is under a new package name so as to not conflict with
  # the standard version in nixpkgs.
  wlroots-hyprland = final: prev: {
    wlroots-hyprland = final.callPackage ./wlroots.nix {
      version = "${mkDate (inputs.wlroots.lastModifiedDate or "19700101")}_${inputs.wlroots.shortRev or "dirty"}";
      src = inputs.wlroots;
      libdisplay-info = prev.libdisplay-info.overrideAttrs (old: {
        version = "0.1.1+date=2023-03-02";
        src = final.fetchFromGitLab {
          domain = "gitlab.freedesktop.org";
          owner = "emersion";
          repo = old.pname;
          rev = "147d6611a64a6ab04611b923e30efacaca6fc678";
          sha256 = "sha256-/q79o13Zvu7x02SBGu0W5yQznQ+p7ltZ9L6cMW5t/o4=";
        };
      });
      libliftoff = prev.libliftoff.overrideAttrs (old: {
        version = "0.5.0-dev";
        src = final.fetchFromGitLab {
          domain = "gitlab.freedesktop.org";
          owner = "emersion";
          repo = old.pname;
          rev = "d98ae243280074b0ba44bff92215ae8d785658c0";
          sha256 = "sha256-DjwlS8rXE7srs7A8+tHqXyUsFGtucYSeq6X0T/pVOc8=";
        };

        NIX_CFLAGS_COMPILE = toString ["-Wno-error=sign-conversion"];
      });
    };
  };
}
