module forgeauth.paths;

import std.file;
import std.path;
import std.process;
import std.string;

/// Config root: FORGE_AUTH_ROOT, else XDG/AppData forge-auth.
string configRoot(string overrideRoot = null) {
	if (overrideRoot.length)
		return absolutePath(overrideRoot);
	auto env = environment.get("FORGE_AUTH_ROOT", "");
	if (env.length)
		return absolutePath(env);
	version (Windows) {
		auto appdata = environment.get("APPDATA", "");
		if (appdata.length)
			return buildPath(appdata, "forge-auth");
	}
	auto xdg = environment.get("XDG_CONFIG_HOME", "");
	if (xdg.length)
		return buildPath(xdg, "forge-auth");
	auto home = environment.get("HOME", environment.get("USERPROFILE", "."));
	return buildPath(home, ".config", "forge-auth");
}

string instancesPath(string root = null) {
	return buildPath(configRoot(root), "instances.sdl");
}

string tokensDir(string root = null) {
	return buildPath(configRoot(root), "tokens");
}

void ensureConfigDirs(string root = null) {
	mkdirRecurse(configRoot(root));
	mkdirRecurse(tokensDir(root));
}
