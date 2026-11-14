#pragma once

#include <filesystem>
#include <optional>
#include <string>

// Helpers for "Use an existing config": relative paths in that file are
// resolved against the config's directory, not the process cwd (Basecamp's
// logos_host often inherits an unrelated cwd).
namespace config_paths {
    // True for POSIX absolute paths and for Windows drive-letter paths even
    // when this code is compiled on Linux (so a C:/... value in a YAML file
    // is not treated as relative).
    [[nodiscard]] bool is_absolute(const std::filesystem::path& p);

    // Empty `configured` means the node default, ./state.
    [[nodiscard]] std::filesystem::path resolve_state_base_folder(
        const std::filesystem::path& config_file,
        const std::string& configured
    );

    // The /state/base_folder scalar, if the file exists and parses. nullopt
    // if the file cannot be read; empty string if the key is absent.
    [[nodiscard]] std::optional<std::string> read_state_base_folder(
        const std::filesystem::path& config_file
    );

    void set_env(const char* name, const std::string& value);
    void unset_env(const char* name);
    [[nodiscard]] std::optional<std::string> get_env(const char* name);
}
