const std = @import("std");
const net = std.net;
const thread = std.Thread;
const stdout = std.io.getStdOut().writer();

const Response = struct { status: []const u8, headers: []const u8, body: []const u8 };

pub fn handleRequest(connection: std.net.Server.Connection) !void {
    defer connection.stream.close();

    try stdout.print("client connected!\n", .{});

    var request: [128]u8 = undefined;
    _ = try connection.stream.read(&request);

    var parts = std.mem.splitAny(u8, &request, " \r\n");
    _ = parts.next().?;
    var reponse = Response{ .status = "", .headers = "", .body = "" };

    if (std.mem.eql(u8, parts.peek().?, "/")) {
        reponse.status = "HTTP/1.1 200 OK";
    } else if (std.mem.startsWith(u8, parts.peek().?, "/echo")) {
        var string = std.mem.splitAny(u8, parts.next().?, "/");
        _ = string.next().?;
        _ = string.next().?;

        const word = string.peek().?;

        const headers = try std.fmt.allocPrint(std.heap.page_allocator, "Content-Type: text/plain\r\nContent-Length: {d}\r\n", .{word.len});

        reponse.status = "HTTP/1.1 200 OK";
        reponse.headers = headers;
        reponse.body = word;
    } else if (std.mem.eql(u8, parts.peek().?, "/user-agent")) {
        reponse.status = "HTTP/1.1 200 OK";

        while (parts.peek() != null) {
            const field = parts.next().?;

            if (std.mem.eql(u8, field, "User-Agent:")) {
                const userAgent = parts.peek().?;
                reponse.body = userAgent;
                reponse.headers = try std.fmt.allocPrint(std.heap.page_allocator, "Content-Type: text/plain\r\nContent-Length: {d}\r\n", .{userAgent.len});
            }
        }
    } else {
        reponse.status = "HTTP/1.1 404 Not Found";
    }

    std.debug.print("Here", .{});

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
