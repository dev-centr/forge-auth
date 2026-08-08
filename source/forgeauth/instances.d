module forgeauth.instances;

import std.file;
import std.path;
import std.string;
import std.algorithm;
import std.stdio;
import sdlang;
import forgeauth.types;
import forgeauth.paths;

ForgeInstance[] loadInstances(string root = null) {
	ForgeInstance[] list;
	auto path = instancesPath(root);
	if (!exists(path)) {
		// Sensible defaults when no file yet
		list ~= ForgeInstance("github.com", ForgeKind.github, "", AuthMode.cli, "", "", "gh");
		list ~= ForgeInstance("gitlab.com", ForgeKind.gitlab, "", AuthMode.cli, "", "", "glab");
		return list;
	}
	try {
		Tag doc = parseSource(readText(path));
		foreach (tag; doc.tags) {
			if (tag.name != "instance") continue;
			ForgeInstance inst;
			inst.id = tag.values[0].get!string;
			foreach (child; tag.tags) {
				if (child.values.length == 0) continue;
				auto v = child.values[0].get!string;
				switch (child.name) {
				case "kind":
					inst.kind = parseKind(v);
					break;
				case "base_url":
					inst.baseUrl = v;
					break;
				case "auth":
					inst.auth = parseAuth(v);
					break;
				case "oauth_client_id":
					inst.oauthClientId = v;
					break;
				case "token_file":
					inst.tokenFile = v;
					break;
				case "cli":
					inst.cliTool = v;
					break;
				default:
					break;
				}
			}
			if (inst.cliTool.length == 0) {
				if (inst.kind == ForgeKind.gitlab) inst.cliTool = "glab";
				else inst.cliTool = "gh";
			}
			list ~= inst;
		}
	} catch (Exception e) {
		stderr.writeln("forge-auth: failed to parse instances.sdl: ", e.msg);
	}
	return list;
}

ForgeInstance* findInstance(ref ForgeInstance[] list, string host) {
	foreach (ref i; list) {
		if (i.id == host) return &i;
	}
	return null;
}

string apiBase(const ref ForgeInstance inst) {
	if (inst.baseUrl.length) return inst.baseUrl.stripRight("/");
	return "https://" ~ inst.id;
}

private ForgeKind parseKind(string s) {
	auto t = s.toLower;
	if (t == "github") return ForgeKind.github;
	if (t == "gitlab") return ForgeKind.gitlab;
	return ForgeKind.unknown;
}

private AuthMode parseAuth(string s) {
	auto t = s.toLower;
	if (t == "oauth") return AuthMode.oauth;
	if (t == "cli") return AuthMode.cli;
	return AuthMode.pat;
}
