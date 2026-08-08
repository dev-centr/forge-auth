module forgeauth.oauth;

import std.stdio;
import std.string;
import std.conv;
import std.process;
import std.net.curl;
import std.json;
import std.datetime;
import std.file;
import forgeauth.types;
import forgeauth.paths;
import forgeauth.tokens;
import forgeauth.instances;

/// Result of starting a device-code OAuth flow.
struct DeviceFlowStart {
	string deviceCode;
	string userCode;
	string verificationUri;
	int intervalSec = 5;
	int expiresInSec = 900;
}

/**
 * Start GitHub device flow. Requires oauth_client_id on the instance.
 * See https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
 */
DeviceFlowStart startGithubDeviceFlow(string clientId) {
	DeviceFlowStart d;
	auto postBody = "client_id=" ~ clientId ~ "&scope=repo%20read:org%20read:user";
	auto http = HTTP();
	http.addRequestHeader("Accept", "application/json");
	auto raw = cast(string) post("https://github.com/login/device/code", postBody, http);
	auto j = parseJSON(raw);
	d.deviceCode = j["device_code"].str;
	d.userCode = j["user_code"].str;
	d.verificationUri = j["verification_uri"].str;
	if ("interval" in j) d.intervalSec = cast(int) j["interval"].integer;
	if ("expires_in" in j) d.expiresInSec = cast(int) j["expires_in"].integer;
	return d;
}

/// Poll until the user completes device authorization; store token on success.
string pollGithubDeviceToken(string clientId, DeviceFlowStart flow, string host = "github.com", string root = null) {
	import core.thread : Thread;
	import core.time : seconds;

	auto deadline = Clock.currTime + dur!"seconds"(flow.expiresInSec);
	while (Clock.currTime < deadline) {
		Thread.sleep(seconds(flow.intervalSec));
		auto postBody = "client_id=" ~ clientId ~ "&device_code=" ~ flow.deviceCode
			~ "&grant_type=urn:ietf:params:oauth:grant-type:device_code";
		auto http = HTTP();
		http.addRequestHeader("Accept", "application/json");
		try {
			auto raw = cast(string) post("https://github.com/login/oauth/access_token", postBody, http);
			auto j = parseJSON(raw);
			if ("access_token" in j) {
				auto tok = j["access_token"].str;
				storePat(host, tok, root);
				return tok;
			}
			if ("error" in j) {
				auto err = j["error"].str;
				if (err == "authorization_pending" || err == "slow_down") {
					if (err == "slow_down") flow.intervalSec += 5;
					continue;
				}
				throw new Exception("OAuth error: " ~ err);
			}
		} catch (Exception e) {
			if (!e.msg.startsWith("OAuth error"))
				continue;
			throw e;
		}
	}
	throw new Exception("OAuth device flow timed out");
}

/// Interactive helper: print user code, open browser, poll, store token.
string loginGithubInteractive(string clientId, string root = null) {
	auto flow = startGithubDeviceFlow(clientId);
	writeln("Open ", flow.verificationUri, " and enter code: ", flow.userCode);
	tryOpenUrl(flow.verificationUri);
	return pollGithubDeviceToken(clientId, flow, "github.com", root);
}

/**
 * GitLab device flow (gitlab.com or self-hosted).
 * baseUrl e.g. https://gitlab.com
 */
DeviceFlowStart startGitlabDeviceFlow(string baseUrl, string clientId) {
	DeviceFlowStart d;
	auto url = baseUrl.stripRight("/") ~ "/oauth/authorize_device";
	auto postBody = "client_id=" ~ clientId ~ "&scope=read_api%20read_repository";
	auto http = HTTP();
	http.addRequestHeader("Accept", "application/json");
	auto raw = cast(string) post(url, postBody, http);
	auto j = parseJSON(raw);
	d.deviceCode = j["device_code"].str;
	d.userCode = j["user_code"].str;
	d.verificationUri = ("verification_uri" in j) ? j["verification_uri"].str : (baseUrl ~ "/oauth/device");
	if ("interval" in j) d.intervalSec = cast(int) j["interval"].integer;
	if ("expires_in" in j) d.expiresInSec = cast(int) j["expires_in"].integer;
	return d;
}

string pollGitlabDeviceToken(string baseUrl, string clientId, DeviceFlowStart flow, string host, string root = null) {
	import core.thread : Thread;
	import core.time : seconds;

	auto tokenUrl = baseUrl.stripRight("/") ~ "/oauth/token";
	auto deadline = Clock.currTime + dur!"seconds"(flow.expiresInSec);
	while (Clock.currTime < deadline) {
		Thread.sleep(seconds(flow.intervalSec));
		auto postBody = "client_id=" ~ clientId ~ "&device_code=" ~ flow.deviceCode
			~ "&grant_type=urn:ietf:params:oauth:grant-type:device_code";
		auto http = HTTP();
		http.addRequestHeader("Accept", "application/json");
		try {
			auto raw = cast(string) post(tokenUrl, postBody, http);
			auto j = parseJSON(raw);
			if ("access_token" in j) {
				auto tok = j["access_token"].str;
				storePat(host, tok, root);
				return tok;
			}
			if ("error" in j) {
				auto err = j["error"].str;
				if (err == "authorization_pending" || err == "slow_down") {
					if (err == "slow_down") flow.intervalSec += 5;
					continue;
				}
				throw new Exception("OAuth error: " ~ err);
			}
		} catch (Exception e) {
			if (!e.msg.startsWith("OAuth error"))
				continue;
			throw e;
		}
	}
	throw new Exception("OAuth device flow timed out");
}

/// Login using instance registry entry (oauth mode).
string loginInstance(string host, string root = null) {
	auto list = loadInstances(root);
	auto inst = findInstance(list, host);
	if (inst is null)
		throw new Exception("Unknown instance: " ~ host);
	if (inst.oauthClientId.length == 0)
		throw new Exception("Set oauth_client_id for " ~ host);
	if (inst.kind == ForgeKind.gitlab) {
		auto base = apiBase(*inst);
		auto flow = startGitlabDeviceFlow(base, inst.oauthClientId);
		writeln("Open ", flow.verificationUri, " and enter code: ", flow.userCode);
		tryOpenUrl(flow.verificationUri);
		return pollGitlabDeviceToken(base, inst.oauthClientId, flow, host, root);
	}
	return loginGithubInteractive(inst.oauthClientId, root);
}

void tryOpenUrl(string url) {
	try {
		version (Windows)
			execute(["cmd", "/c", "start", "", url]);
		else version (OSX)
			execute(["open", url]);
		else
			execute(["xdg-open", url]);
	} catch (Exception) {}
}
