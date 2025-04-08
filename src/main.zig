const std = @import("std");
const net = std.net;
const thread = std.Thread;
const stdout = std.io.getStdOut().writer();

const Response = struct { status: []const u8, headers: []const u8, body: []const u8 };

const Request = struct {
    requestLine: []const u8 = "",
    header: []const u8 = "",
    body: []const u8 = "",

    pub fn parse(self: *Request, request: []u8) !void {
        var data = std.mem.splitSequence(u8, request, "\r\n\r\n");

        const requestLineAndHeader = data.first();
        self.body = data.rest();

        var fields = std.mem.splitSequence(u8, requestLineAndHeader, "\r\n");
        self.requestLine = fields.first();
        self.header = fields.rest();
    }

    pub fn getRoute(self: *Request) []const u8 {
        var fields = std.mem.splitSequence(u8, self.requestLine, " ");
        _ = fields.next();

        return fields.next().?;
    }

    pub fn getHeader(self: *Request, header: []const u8) ?[]const u8 {
        var fields = std.mem.splitSequence(u8, self.header, "\r\n");

        while (fields.peek()) |field| : (_ = fields.next()) {
            var key = std.mem.splitSequence(u8, field, ": ");

            if (std.mem.eql(u8, key.first(), header)) {
                return key.rest();
            }
        }

        return null;
    }
};

pub fn handleRequest(connection: std.net.Server.Connection) !void {
    defer connection.stream.close();

    try stdout.print("client connected!\n", .{});

    var requestData: [128]u8 = undefined;
    _ = try connection.stream.read(&requestData);

    var request = Request{};
    try request.parse(&requestData);

    var reponse = Response{ .status = "", .headers = "", .body = "" };

    const route = request.getRoute();

    if (std.mem.eql(u8, route, "/")) {
        reponse.status = "HTTP/1.1 200 OK";
    } else if (std.mem.startsWith(u8, route, "/echo")) {
        const word = route[6..];

        const headers = try std.fmt.allocPrint(std.heap.page_allocator, "Content-Type: text/plain\r\nContent-Length: {d}\r\n", .{word.len});

        reponse.status = "HTTP/1.1 200 OK";
        reponse.headers = headers;
        reponse.body = word;
    } else if (std.mem.eql(u8, route, "/user-agent")) {
        const userAgent = request.getHeader("User-Agent").?;

        reponse.status = "HTTP/1.1 200 OK";
        reponse.headers = try std.fmt.allocPrint(std.heap.page_allocator, "Content-Type: text/plain\r\nContent-Length: {d}\r\n", .{userAgent.len});
        reponse.body = userAgent;
    } else {
        reponse.status = "HTTP/1.1 404 Not Found";
    }

    try sendResponse(connection, reponse);
}

pub fn main() !void {
    while (true) {
        const address = try net.Address.resolveIp("127.0.0.1", 4221);
        var listener = try address.listen(.{
            .reuse_address = true,
        });
        defer listener.deinit();

        const connection = try listener.accept();

        const newThread = try thread.spawn(.{}, handleRequest, .{connection});
        newThread.detach();
    }
}

pub fn sendResponse(conn: std.net.Server.Connection, response: Response) !void {
    const res = try std.fmt.allocPrint(std.heap.page_allocator, "{s}\r\n{s}\r\n{s}\r\n", .{ response.status, response.headers, response.body });

    std.debug.print("{s}", .{res});

    _ = try conn.stream.writeAll(res);
}
