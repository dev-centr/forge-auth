module forgeauth.tokens;

import std.file;
import std.path;
import std.process;
import std.string;
import std.stdio;
import std.array;
import std.algorithm : canFind;
import forgeauth.types;
import forgeauth.paths;
import forgeauth.instances;

/// Resolve a credential for host. Order: env, token file, cli auth token.
Credential resolveCredential(string host, string root = null) {
	Credential c;
	c.host = host;
	auto envKey = "FORGE_TOKEN_" ~ host.replace(".", "_").replace("-", "_");
	string envKeyUpper;
	foreach (ch; envKey) {
		if (ch >= 'a' && ch <= 'z') envKeyUpper ~= cast(char)(ch - 32);
		else envKeyUpper ~= ch;
	}
	envKey = envKeyUpper;
	auto envTok = environment.get(envKey, "");
	if (envTok.length == 0)
		envTok = environment.get("FORGE_TOKEN", "");
	if (envTok.length) {
		c.token = envTok.strip;
		c.source = "env";
		return c;
	}

	auto list = loadInstances(root);
	auto inst = findInstance(list, host);
	if (inst !is null) {
		auto tokPath = resolveTokenPath(*inst, root);
		if (tokPath.length && exists(tokPath)) {
			c.token = readText(tokPath).strip;
			c.source = inst.auth == AuthMode.oauth ? "oauth" : "pat";
			if (c.token.length) return c;
		}
		if (inst.auth == AuthMode.cli || c.token.length == 0) {
			auto cliTok = readCliToken(inst.cliTool.length ? inst.cliTool : "gh");
			if (cliTok.length) {
				c.token = cliTok;
				c.source = "cli";
				return c;
			}
		}
	} else {
		auto cliTok = readCliToken(host.indexOf("gitlab") >= 0 ? "glab" : "gh");
		if (cliTok.length) {
			c.token = cliTok;
			c.source = "cli";
			return c;
		}
	}
	return c;
}

void storePat(string host, string token, string root = null) {
	ensureConfigDirs(root);
	auto path = buildPath(tokensDir(root), host ~ ".token");
	std.file.write(path, token.strip ~ "\n");
}

string resolveTokenPath(const ref ForgeInstance inst, string root = null) {
	if (inst.tokenFile.length) {
		if (isAbsolute(inst.tokenFile)) return inst.tokenFile;
		return buildPath(configRoot(root), inst.tokenFile);
	}
	return buildPath(tokensDir(root), inst.id ~ ".token");
}

/// Best-effort: `gh auth token` / `glab auth token`.
string readCliToken(string tool) {
	try {
		auto p = execute([tool, "auth", "token"]);
		if (p.status == 0)
			return p.output.strip;
	} catch (Exception) {}
	return "";
}
