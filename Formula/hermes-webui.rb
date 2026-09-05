class HermesWebui < Formula
  desc "Lightweight, dark-themed web interface for Hermes Agent"
  homepage "https://github.com/nesquena/hermes-webui"
  url "https://github.com/nesquena/hermes-webui/archive/refs/tags/exp-v0.52.264.tar.gz"
  sha256 "b6f89476986da87182b69a30d319db39d3c85679b392c2bca73a8ffe8fd5941b"
  license "MIT"
  head "https://github.com/nesquena/hermes-webui.git", branch: "master"

  depends_on "python@3.12"
  depends_on "python-setuptools"

  def install
    # The package uses setuptools with a console script entry point
    # Install into a dedicated prefix and link the console script
    system "pip3", "install", *std_pip_args, "."

    # Create state directories (like hermes-workspace formula)
    (var/"lib/hermes-webui").mkpath
    (var/"log/hermes-webui").mkpath
    (var/"hermes-webui").mkpath
  end

  service do
    run [opt_bin/"hermes-webui", "serve", "--port", "8787"]
    keep_alive true
    environment_variables PATH: std_service_path_env
    working_dir var/"hermes-webui"
    log_path var/"log/hermes-webui.log"
    error_log_path var/"log/hermes-webui.error.log"
  end

  test do
    # Test that the console script is available and shows version
    assert_match "hermes-webui", shell_output("#{bin}/hermes-webui --help 2>&1")
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

  def post_install
    service_name = "homebrew.#{name}"

    if OS.linux?
      service_file = Pathname.new(Dir.home)/".config"/"systemd"/"user"/"#{service_name}.service"
      expected_working_dir = var/"hermes-webui"
      expected_path = std_service_path_env

      if service_file.exist?
        content = service_file.read
        issues = []

        unless content.include?("WorkingDirectory=#{expected_working_dir}")
          issues << "WorkingDirectory mismatch (expected: #{expected_working_dir})"
        end

        unless content.include?("Environment=PATH=#{expected_path}")
          issues << "Environment=PATH mismatch (expected: #{expected_path})"
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
      expected_path = std_service_path_env

      if plist_file.exist?
        content = plist_file.read
        issues = []

        unless content.include?("<key>EnvironmentVariables</key>") &&
               content.include?("<key>PATH</key>") &&
               content.include?("<string>#{expected_path}</string>")
          issues << "EnvironmentVariables/PATH missing or incorrect (expected: #{expected_path})"
        end

        unless content.include?("<key>WorkingDirectory</key>") &&
               content.include?("<string>#{expected_working_dir}</string>")
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
