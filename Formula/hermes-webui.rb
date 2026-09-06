class HermesWebui < Formula
  desc "Lightweight, dark-themed web interface for Hermes Agent"
  homepage "https://github.com/nesquena/hermes-webui"
  url "https://github.com/nesquena/hermes-webui/archive/refs/tags/exp-v0.52.264.tar.gz"
  sha256 "b6f89476986da87182b69a30d319db39d3c85679b392c2bca73a8ffe8fd5941b"
  license "MIT"
  head "https://github.com/nesquena/hermes-webui.git", branch: "master"

  depends_on "python-setuptools"
  depends_on "python@3.12"

  def install
    system "pip3", "install", *std_pip_args, "."

    # pyyaml is not packaged in Homebrew core; cryptography's formula targets
    # python@3.13/3.14, not python@3.12. Install both (plus cffi, which
    # cryptography requires at runtime) via pip wheels. std_pip_args would force
    # --no-binary=:all: (source builds), so cryptography would need maturin —
    # avoid that by passing explicit args that allow wheels. Use --target so
    # pip puts its bin scripts (e.g. cffi-gen-src) inside site-packages instead
    # of the keg's bin/, which would clash with the cffi formula at brew link.
    site_packages = prefix/Language::Python.site_packages("python3.12")
    system "pip3", "install",
           "--target=#{site_packages}",
           "--ignore-installed",
           "--no-compile",
           "--no-deps",
           "pyyaml>=6.0", "cryptography>=42.0", "cffi"

    (var/"lib/hermes-webui").mkpath
    (var/"log/hermes-webui").mkpath
    (var/"hermes-webui").mkpath

    # Create a wrapper that bypasses bootstrap.py (which requires Hermes Agent)
    # and runs server.py directly with the Homebrew Python. pip's console
    # script already exists at bin/hermes-webui, so unlink it first --
    # Pathname#write refuses to overwrite an existing file.
    (bin/"hermes-webui").unlink if (bin/"hermes-webui").exist?
    (bin/"hermes-webui").write <<~PYTHON
      #!#{Formula["python@3.12"].opt_bin}/python3.12
      import os
      import sys

      # Default port
      port = 8787

      # Parse simple args: port as positional, --foreground, --no-browser
      args = sys.argv[1:]
      foreground = "--foreground" in args
      no_browser = "--no-browser" in args
      args = [a for a in args if a not in ("--foreground", "--no-browser")]

      if args:
          try:
              port = int(args[0])
          except ValueError:
              print(f"Invalid port: {args[0]}", file=sys.stderr)
              sys.exit(1)

      # Set environment for server.py
      os.environ["HERMES_WEBUI_HOST"] = "127.0.0.1"
      os.environ["HERMES_WEBUI_PORT"] = str(port)

      state_dir = os.environ.get("HERMES_WEBUI_STATE_DIR") or os.path.expanduser("~/.hermes/webui")
      os.makedirs(state_dir, exist_ok=True)
      os.environ.setdefault("HERMES_WEBUI_STATE_DIR", state_dir)

      # Locate server.py in the installed package
      pkg_dir = os.path.dirname(os.path.dirname(__file__))
      site_packages = os.path.join(pkg_dir, "lib", "python3.12", "site-packages")
      server_py = os.path.join(site_packages, "server.py")

      if not os.path.exists(server_py):
          # Fallback: look in Cellar
          import glob
          candidates = glob.glob("/home/linuxbrew/.linuxbrew/Cellar/hermes-webui/*/lib/python3.12/site-packages/server.py")
          if candidates:
              server_py = candidates[0]
          else:
              print("ERROR: Cannot find server.py", file=sys.stderr)
              sys.exit(1)

      if foreground:
          os.execv(sys.executable, [sys.executable, server_py])
      else:
          import subprocess
          subprocess.Popen(
              [sys.executable, server_py],
              start_new_session=True,
              stdout=subprocess.DEVNULL,
              stderr=subprocess.DEVNULL,
          )
          print(f"Hermes WebUI starting on http://127.0.0.1:{port}")
    PYTHON

    # Make wrapper executable
    chmod 0755, bin/"hermes-webui"
  end

  service do
    run [opt_bin/"hermes-webui", "8787", "--foreground"]
    keep_alive true
    environment_variables PATH: std_service_path_env
    working_dir var/"hermes-webui"
    log_path var/"log/hermes-webui.log"
    error_log_path var/"log/hermes-webui.error.log"
  end

  def caveats
    <<~EOS
      Start the service (user-level deployment):
        brew services start #{name}

      On Linux, enable lingering so the service persists after logout and starts on boot:
        loginctl enable-linger $USER

      On macOS, launchd services run under restricted OS security policies (TCC).
      If hermes-webui requires access to protected user directories (e.g. ~/Desktop,
      ~/Downloads, ~/Documents), grant "Full Disk Access" to your terminal application
      and the node/python binaries in System Settings > Privacy & Security.
    EOS
  end

  test do
    assert_match "hermes-webui", shell_output("#{bin}/hermes-webui --help 2>&1")
  end

  def post_install_steps
    service_name = "homebrew.#{name}"

    if OS.linux?
      service_file = Pathname.new(Dir.home)/".config"/"systemd"/"user"/"#{service_name}.service"
      expected_working_dir = var/"hermes-webui"

      if service_file.exist?
        content = service_file.read
        issues = []

        if content.exclude?("WorkingDirectory=#{expected_working_dir}")
          issues << "WorkingDirectory mismatch (expected: #{expected_working_dir})"
        end

        if issues.empty?
          ohai "Service file #{service_file} validates successfully"
        else
          opoo "Service file #{service_file} has issues:\n  #{issues.join("\n  ")}"
        end
      else
        ohai "Service file #{service_file} not found — it will be generated on first `brew services start #{name}`"
      end
    elsif OS.mac?
      plist_file = Pathname.new(Dir.home)/"Library"/"LaunchAgents"/"#{service_name}.plist"
      expected_working_dir = var/"hermes-webui"

      if plist_file.exist?
        content = plist_file.read
        issues = []

        if content.exclude?("<key>EnvironmentVariables</key>")
          issues << "EnvironmentVariables/PATH missing"
        elsif content.exclude?("<key>PATH</key>")
          issues << "EnvironmentVariables/PATH missing"
        end

        if content.exclude?("<key>WorkingDirectory</key>")
          issues << "WorkingDirectory missing"
        elsif content.exclude?("<string>#{expected_working_dir}</string>")
          issues << "WorkingDirectory missing or incorrect (expected: #{expected_working_dir})"
        end

        if issues.empty?
          ohai "LaunchAgent plist #{plist_file} validates successfully"
        else
          opoo "LaunchAgent plist #{plist_file} has issues:\n  #{issues.join("\n  ")}"
        end
      else
        ohai "LaunchAgent plist #{plist_file} not found — it will be generated on first `brew services start #{name}`"
      end
    end
  end
end
