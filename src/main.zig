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

    pub fn getMethod(self: *Request) []const u8 {
        var fields = std.mem.splitSequence(u8, self.requestLine, " ");

        return fields.next().?;
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
    const allocator = std.heap.page_allocator;

    defer connection.stream.close();

    try stdout.print("client connected!\n", .{});

    var requestData: [256]u8 = undefined;
    _ = try connection.stream.read(&requestData);

    var request = Request{};
    try request.parse(&requestData);

    var response = Response{ .status = "", .headers = "", .body = "" };

    const route = request.getRoute();
    const method = request.getMethod();

    // POST Requests
    if (std.mem.eql(u8, method, "POST")) {
        const filename = route[7..];
        const filepath = try getFilePath(filename);

        const file = try std.fs.createFileAbsolute(filepath, .{});
        defer file.close();

        const length = try std.fmt.parseInt(usize, request.getHeader("Content-Length").?, 0);

        try file.writeAll(request.body[0..length]);

        response.status = "HTTP/1.1 201 Created";
        try sendResponse(connection, response);
        return;
    }

    // GET Requests
    if (std.mem.eql(u8, route, "/")) {
        response.status = "HTTP/1.1 200 OK";
    } else if (std.mem.startsWith(u8, route, "/echo")) {
        const word = route[6..];

        const acceptEncodings = request.getHeader("Accept-Encoding");

        if (acceptEncodings != null and std.mem.containsAtLeast(u8, acceptEncodings.?, 1, "gzip")) {
            var compressedBody = std.ArrayList(u8).init(allocator);

            var fbs = std.io.fixedBufferStream(word);

            try std.compress.gzip.compress(fbs.reader(), compressedBody.writer(), .{});

            const headers = try std.fmt.allocPrint(allocator, "Content-Encoding: gzip\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n", .{compressedBody.items.len});

            response.headers = headers;
            response.body = compressedBody.items;
        } else {
            const headers = try std.fmt.allocPrint(allocator, "Content-Type: text/plain\r\nContent-Length: {d}\r\n", .{word.len});

            response.headers = headers;
            response.body = word;
        }

        response.status = "HTTP/1.1 200 OK";
    } else if (std.mem.eql(u8, route, "/user-agent")) {
        const userAgent = request.getHeader("User-Agent").?;

        response.status = "HTTP/1.1 200 OK";
        response.headers = try std.fmt.allocPrint(allocator, "Content-Type: text/plain\r\nContent-Length: {d}\r\n", .{userAgent.len});
        response.body = userAgent;
    } else if (std.mem.startsWith(u8, route, "/files")) {
        const filename = route[7..];
        const filepath = try getFilePath(filename);

        const file = std.fs.cwd().openFile(filepath, .{}) catch null;

        if (file) |f| {
            defer f.close();

            var fileContent: [1024]u8 = undefined;
            const fileSize = try f.read(&fileContent);

            const headers = try std.fmt.allocPrint(allocator, "Content-Type: application/octet-stream\r\nContent-Length: {d}\r\n", .{fileSize});

            response.status = "HTTP/1.1 200 OK";
            response.headers = headers;
            response.body = &fileContent;
        } else {
            response.status = "HTTP/1.1 404 Not Found";
        }
    } else {
        response.status = "HTTP/1.1 404 Not Found";
    }

    try sendResponse(connection, response);
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

    _ = try conn.stream.writeAll(res);
}

pub fn getFilePath(filename: []const u8) ![]u8 {
    const allocator = std.heap.page_allocator;
    var dirname: []u8 = undefined;

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--directory")) {
            dirname = @constCast(args.next().?);
        }
    }

    return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dirname, filename });
}
