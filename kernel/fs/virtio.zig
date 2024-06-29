const fs = @import("fs.zig");
const lib = @import("../lib.zig");
const riscv = @import("../riscv.zig");

const KMem = @import("../mem/kmem.zig");

const Process = @import("../procs/proc.zig");
const Buffer = @import("buffer.zig");
const Spinlock = @import("../locks/spinlock.zig");

inline fn virtioRegister(reg: u32) *volatile u32 {
    return @ptrFromInt(riscv.VIRTIO0 + reg);
}

const NUM_DESC = 8;

const VIRTIO_MMIO_MAGIC_VALUE = 0x000; // 0x74726976
const VIRTIO_MMIO_VERSION = 0x004; // version; should be 2
const VIRTIO_MMIO_DEVICE_ID = 0x008; // device type; 1 is net, 2 is disk
const VIRTIO_MMIO_VENDOR_ID = 0x00c; // 0x554d4551
const VIRTIO_MMIO_DEVICE_FEATURES = 0x010;
const VIRTIO_MMIO_DRIVER_FEATURES = 0x020;
const VIRTIO_MMIO_QUEUE_SEL = 0x030; // select queue, write-only
const VIRTIO_MMIO_QUEUE_NUM_MAX = 0x034; // max size of current queue, read-only
const VIRTIO_MMIO_QUEUE_NUM = 0x038; // size of current queue, write-only
const VIRTIO_MMIO_QUEUE_READY = 0x044; // ready bit
const VIRTIO_MMIO_QUEUE_NOTIFY = 0x050; // write-only
const VIRTIO_MMIO_INTERRUPT_STATUS = 0x060; // read-only
const VIRTIO_MMIO_INTERRUPT_ACK = 0x064; // write-only
const VIRTIO_MMIO_STATUS = 0x070; // read/write
const VIRTIO_MMIO_QUEUE_DESC_LOW = 0x080; // physical address for descriptors table, write-only
const VIRTIO_MMIO_QUEUE_DESC_HIGH = 0x084;
const VIRTIO_MMIO_DRIVER_DESC_LOW = 0x090; // physical address for available ring, write-only
const VIRTIO_MMIO_DRIVER_DESC_HIGH = 0x094;
const VIRTIO_MMIO_DEVICE_DESC_LOW = 0x0a0; // physical address for used ring, write-only
const VIRTIO_MMIO_DEVICE_DESC_HIGH = 0x0a4;

const VIRTIO_CONFIG_S_ACKNOWLEDGE = 1;
const VIRTIO_CONFIG_S_DRIVER = 2;
const VIRTIO_CONFIG_S_DRIVER_OK = 4;
const VIRTIO_CONFIG_S_FEATURES_OK = 8;

// device feature bits
const VIRTIO_BLK_F_RO = 5; // Disk is read-only
const VIRTIO_BLK_F_SCSI = 7; // Supports scsi command passthru
const VIRTIO_BLK_F_CONFIG_WCE = 11; // Writeback mode available in config
const VIRTIO_BLK_F_MQ = 12; // support more than one vq
const VIRTIO_F_ANY_LAYOUT = 27;
const VIRTIO_RING_F_INDIRECT_DESC = 28;
const VIRTIO_RING_F_EVENT_IDX = 29;

const VIRTIO_BLK_T_IN = 0; // read the disk
const VIRTIO_BLK_T_OUT = 1; // write the disk

const VRING_DESC_F_NEXT = 1; // chained with another descriptor
const VRING_DESC_F_WRITE = 2; // device writes (vs read)

const Descriptor = extern struct {
    addr: u64,
    len: u32,
    flags: u16,
    next: u16,
};

const Available = extern struct {
    flags: u16,
    idx: u16,
    ring: [NUM_DESC]u16,
    _: u16,
};

const UsedElement = extern struct {
    id: u32,
    len: u32,
};

const Used = extern struct {
    flags: u16,
    idx: u16,
    ring: [NUM_DESC]UsedElement,
};

const BlockRequest = extern struct {
    typ: u32,
    reserved: u32,
    sector: u64,
};

const Info = extern struct {
    buffer: *Buffer,
    status: u8,
};

var lock: Spinlock = undefined;
var descriptors: *[NUM_DESC]Descriptor = undefined;
var available: *Available = undefined;
var used: *Used = undefined;
var used_index: u16 = 0;

var free: [NUM_DESC]u8 = undefined;
var free_index: u16 = undefined;
var info: [NUM_DESC]Info = undefined;
var block_requests: [NUM_DESC]BlockRequest = undefined;

pub fn init() void {
    var status: u32 = 0;
    lock = Spinlock.init("virtio disk");
    if (virtioRegister(VIRTIO_MMIO_MAGIC_VALUE).* != 0x74726976 or
        virtioRegister(VIRTIO_MMIO_VERSION).* != 2 or
        virtioRegister(VIRTIO_MMIO_DEVICE_ID).* != 2 or
        virtioRegister(VIRTIO_MMIO_VENDOR_ID).* != 0x554d4551)
    {
        lib.kpanic("virtio: failed to initialize");
    }

    virtioRegister(VIRTIO_MMIO_STATUS).* = status;

    status |= VIRTIO_CONFIG_S_ACKNOWLEDGE;
    virtioRegister(VIRTIO_MMIO_STATUS).* = status;

    status |= VIRTIO_CONFIG_S_DRIVER;
    virtioRegister(VIRTIO_MMIO_STATUS).* = status;

    var features = virtioRegister(VIRTIO_MMIO_DEVICE_FEATURES).*;
    features &= ~(@as(u32, 1) << VIRTIO_BLK_F_RO);
    features &= ~(@as(u32, 1) << VIRTIO_BLK_F_SCSI);
    features &= ~(@as(u32, 1) << VIRTIO_BLK_F_CONFIG_WCE);
    features &= ~(@as(u32, 1) << VIRTIO_BLK_F_MQ);
    features &= ~(@as(u32, 1) << VIRTIO_F_ANY_LAYOUT);
    features &= ~(@as(u32, 1) << VIRTIO_RING_F_EVENT_IDX);
    features &= ~(@as(u32, 1) << VIRTIO_RING_F_INDIRECT_DESC);
    virtioRegister(VIRTIO_MMIO_DEVICE_FEATURES).* = features;

    status |= VIRTIO_CONFIG_S_FEATURES_OK;
    virtioRegister(VIRTIO_MMIO_STATUS).* = status;

    status = virtioRegister(VIRTIO_MMIO_STATUS).*;

    if ((status & VIRTIO_CONFIG_S_FEATURES_OK) == 0) {
        lib.kpanic("virtio: features ok unset");
    }

    if (virtioRegister(VIRTIO_MMIO_QUEUE_READY).* != 0) {
        lib.kpanic("virtio: queue ready in use");
    }

    const max = virtioRegister(VIRTIO_MMIO_QUEUE_NUM_MAX).*;
    if (max == 0) {
        lib.kpanic("virtio: queue has no disk 0");
    }
    if (max < NUM_DESC) {
        lib.kpanic("virtio: queue num max too short");
    }

    const descriptor_page = KMem.alloc() catch lib.kpanic("virtio: failed to allocate descriptors");
    const available_page = KMem.alloc() catch lib.kpanic("virtio: failed to allocate available");
    const used_page = KMem.alloc() catch lib.kpanic("virtio: failed to allocate used");

    const descriptor_arr: *riscv.Page = @ptrCast(descriptor_page);
    const available_arr: *riscv.Page = @ptrCast(available_page);
    const used_arr: *riscv.Page = @ptrCast(used_page);

    @memset(descriptor_arr, 0);
    @memset(available_arr, 0);
    @memset(used_arr, 0);

    descriptors = @ptrCast(@alignCast(descriptor_arr));
    available = @ptrCast(@alignCast(available_arr));
    used = @ptrCast(@alignCast(used_arr));

    virtioRegister(VIRTIO_MMIO_QUEUE_NUM).* = NUM_DESC;

    const descriptor_ptr: u64 = @intFromPtr(descriptors);
    const available_ptr: u64 = @intFromPtr(available);
    const used_ptr: u64 = @intFromPtr(used);

    virtioRegister(VIRTIO_MMIO_QUEUE_DESC_LOW).* = @truncate(descriptor_ptr);
    virtioRegister(VIRTIO_MMIO_QUEUE_DESC_HIGH).* = @truncate(descriptor_ptr >> 32);

    virtioRegister(VIRTIO_MMIO_DRIVER_DESC_LOW).* = @truncate(available_ptr);
    virtioRegister(VIRTIO_MMIO_DRIVER_DESC_HIGH).* = @truncate(available_ptr >> 32);

    virtioRegister(VIRTIO_MMIO_DEVICE_DESC_LOW).* = @truncate(used_ptr);
    virtioRegister(VIRTIO_MMIO_DEVICE_DESC_HIGH).* = @truncate(used_ptr >> 32);

    virtioRegister(VIRTIO_MMIO_QUEUE_READY).* = 1;

    for (&free) |*f| {
        f.* = 1;
    }

    status |= VIRTIO_CONFIG_S_DRIVER_OK;
    virtioRegister(VIRTIO_MMIO_STATUS).* = status;
}

pub fn readTo(buf: *Buffer) void {
    read_write(buf, false);
}

pub fn writeFrom(buf: *Buffer) void {
    read_write(buf, true);
}

pub fn diskInterrupt() void {
    lock.acquire();
    defer lock.release();

    const status = virtioRegister(VIRTIO_MMIO_INTERRUPT_STATUS).*;

    virtioRegister(VIRTIO_MMIO_INTERRUPT_ACK).* = status & 0x3;
    @fence(.seq_cst);

    while (used_index != used.idx) {
        @fence(.seq_cst);
        const id = used.ring[used_index % NUM_DESC].id;
        @fence(.seq_cst);

        if (info[id].status != 0) {
            lib.kpanic("virtio: disk interrupt error");
        }

        const buf = info[id].buffer;
        buf.disk_owned = false;
        Process.wakeup(buf);
        used_index += 1;
    }
}

fn read_write(buf: *Buffer, write: bool) void {
    const sector = buf.block_num * @divExact(fs.BLOCK_SIZE, 512);

    lock.acquire();
    defer lock.release();

    const proc = Process.currentOrPanic();

    var indexes: [3]u16 = undefined;

    while (true) {
        alloc3Descriptors(&indexes) catch {
            proc.sleep(&free, &lock);
            continue;
        };
        break;
    }

    var block_request0 = &block_requests[indexes[0]];

    block_request0.typ = if (write) VIRTIO_BLK_T_OUT else VIRTIO_BLK_T_IN;
    block_request0.reserved = 0;
    block_request0.sector = sector;

    descriptors[indexes[0]].addr = @intFromPtr(block_request0);
    descriptors[indexes[0]].len = @sizeOf(BlockRequest);
    descriptors[indexes[0]].flags = VRING_DESC_F_NEXT;
    descriptors[indexes[0]].next = indexes[1];

    const flags: u16 = if (write) 0 else VRING_DESC_F_WRITE;
    descriptors[indexes[1]].addr = @intFromPtr(&buf.data);
    descriptors[indexes[1]].len = fs.BLOCK_SIZE;
    descriptors[indexes[1]].flags = flags | VRING_DESC_F_NEXT;
    descriptors[indexes[1]].next = indexes[2];

    info[indexes[0]].status = 0xFF; // will be 0 on success

    descriptors[indexes[2]].addr = @intFromPtr(&info[indexes[0]].status);
    descriptors[indexes[2]].len = 1;
    descriptors[indexes[2]].flags = VRING_DESC_F_WRITE;
    descriptors[indexes[2]].next = 0;

    buf.disk_owned = true;
    info[indexes[0]].buffer = buf;

    available.ring[available.idx % NUM_DESC] = indexes[0];

    @fence(.seq_cst);
    available.idx += 1;
    @fence(.seq_cst);

    virtioRegister(VIRTIO_MMIO_QUEUE_NOTIFY).* = 0;

    while (buf.disk_owned) {
        proc.sleep(buf, &lock);
    }

    info[indexes[0]].buffer = undefined;
    freeDescriptorChain(indexes[0]);
}

fn alloc3Descriptors(indexes: *[3]u16) !void {
    var i: u16 = 0;
    while (i < 3) : (i += 1) {
        indexes[i] = allocDescriptor() catch {
            for (indexes[0..i]) |d| {
                freeDescriptor(d);
            }
            return error.Under3Descriptors;
        };
    }
}

fn allocDescriptor() !u16 {
    var i: u16 = 0;
    while (i < NUM_DESC) : (i += 1) {
        if (free[i] == 1) {
            free[i] = 0;
            return i;
        }
    }
    return error.NoDescriptors;
}

fn freeDescriptor(index: u16) void {
    if (index >= NUM_DESC) {
        lib.kpanic("virtio: free descriptors out of bounds");
    }
    if (free[index] == 1) {
        lib.kpanic("virtio: free descriptors already free");
    }

    descriptors[index].addr = 0;
    descriptors[index].len = 0;
    descriptors[index].flags = 0;
    descriptors[index].next = 0;
    free[index] = 1;

    Process.wakeup(&free);
}

fn freeDescriptorChain(index: u16) void {
    var i: u16 = index;
    while (true) {
        const flag = descriptors[i].flags;
        const next = descriptors[i].next;
        freeDescriptor(i);
        if (flag & VRING_DESC_F_NEXT == 0) {
            break;
        }
        i = next;
    }
}
