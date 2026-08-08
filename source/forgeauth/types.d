module forgeauth.types;

/// How credentials are obtained for an instance.
enum AuthMode {
	oauth,
	pat,
	cli  /// reuse gh / glab logged-in session
}

/// Forge family for API shape.
enum ForgeKind {
	github,
	gitlab,
	unknown
}

struct ForgeInstance {
	string id;           /// usually host, e.g. github.com
	ForgeKind kind = ForgeKind.github;
	string baseUrl;      /// empty => https://id
	AuthMode auth = AuthMode.pat;
	string oauthClientId;
	string tokenFile;    /// relative to config root or absolute
	string cliTool;      /// gh / glab override
}

struct Credential {
	string host;
	string token;
	string source;       /// oauth | pat | cli | env
}
