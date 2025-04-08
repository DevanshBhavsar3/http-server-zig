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

    if (std.mem.eql(u8, parts.next().?, "/")) {
        try connection.stream.writeAll("HTTP/1.1 200 OK\r\n\r\n");
    } else {
        try connection.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
    }
}
