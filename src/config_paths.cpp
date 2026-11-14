#include "config_paths.h"

#include <cctype>
#include <cstdlib>
#include <libfyaml.h>

#ifdef _WIN32
#    include <stdlib.h>
#endif

namespace fs = std::filesystem;

namespace config_paths {
    bool is_absolute(const fs::path& p) {
        if (p.is_absolute())
            return true;
        const std::string s = p.generic_string();
        return s.size() >= 3 && std::isalpha(static_cast<unsigned char>(s[0])) && s[1] == ':' &&
               (s[2] == '/' || s[2] == '\\');
    }

    fs::path resolve_state_base_folder(const fs::path& config_file, const std::string& configured) {
        fs::path folder = configured.empty() ? fs::path("./state") : fs::path(configured);
        if (!is_absolute(folder)) {
            fs::path parent = config_file.parent_path();
            if (parent.empty())
                parent = ".";
            folder = parent / folder;
        }
        return folder.lexically_normal();
    }

    std::optional<std::string> read_state_base_folder(const fs::path& config_file) {
        fy_document* doc = fy_document_build_from_file(nullptr, config_file.string().c_str());
        if (!doc)
            return std::nullopt;
        fy_node* node = fy_node_by_path(
            fy_document_root(doc), "/state/base_folder", FY_NT, FYNWF_DONT_FOLLOW
        );
        const char* text = node ? fy_node_get_scalar0(node) : nullptr;
        std::string value = text ? text : "";
        fy_document_destroy(doc);
        return value;
    }

    void set_env(const char* name, const std::string& value) {
#ifdef _WIN32
        _putenv_s(name, value.c_str());
#else
        setenv(name, value.c_str(), 1);
#endif
    }

    void unset_env(const char* name) {
#ifdef _WIN32
        _putenv_s(name, "");
#else
        unsetenv(name);
#endif
    }

    std::optional<std::string> get_env(const char* name) {
        const char* v = std::getenv(name);
        if (!v)
            return std::nullopt;
        return std::string(v);
    }
}
