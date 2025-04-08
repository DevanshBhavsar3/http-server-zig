const std = @import("std");
const net = std.net;

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();

    const address = try net.Address.resolveIp("127.0.0.1", 4221);
    var listener = try address.listen(.{
        .reuse_address = true,
    });
    defer listener.deinit();

    const connection = try listener.accept();
    defer connection.stream.close();

    try stdout.print("client connected!\n", .{});

    var request: [128]u8 = undefined;
    _ = try connection.stream.read(&request);

    var parts = std.mem.splitAny(u8, &request, " ");
    _ = parts.next().?;

    if (std.mem.eql(u8, parts.peek().?, "/")) {
        try sendResponse(connection, "HTTP/1.1 200 OK\r\n\r\n");
    } else if (std.mem.startsWith(u8, parts.peek().?, "/echo")) {
        var string = std.mem.splitAny(u8, parts.next().?, "/");
        _ = string.next().?;
        _ = string.next().?;

        const word = string.peek().?;

        const response = try std.fmt.allocPrint(std.heap.page_allocator, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {d}\r\n\r\n{s}", .{ word.len, word });
        try sendResponse(connection, response);
    } else {
        try sendResponse(connection, "HTTP/1.1 404 Not Found\r\n\r\n");
    }
}

pub fn sendResponse(conn: std.net.Server.Connection, response: []const u8) !void {
    _ = try conn.stream.writeAll(response);
}
