pub const ElfHeader = extern struct {
    magic: u32,
    elf: [12]u8,
    typ: u16,
    machine: u16,
    version: u32,
    entry: u64,
    program_header_offset: u64,
    section_header_offset: u64,
    flags: u32,
    header_size: u16,
    program_header_size: u16,
    program_header_count: u16,
    section_header_size: u16,
    section_header_count: u16,
    section_names_index: u16,
};

pub const ProgramHeaderType = enum(u32) {
    LOAD = 1,
    DYNAMIC = 2,
    INTERP = 3,
    NOTE = 4,
    SHLIB = 5,
    PHDR = 6,
};

pub const ProgramHeaderFlag = enum(u32) {
    EXECUTABLE = 1,
    WRITE = 2,
    READ = 4,
};

pub const ProgramHeader = extern struct {
    typ: ProgramHeaderType,
    flags: ProgramHeaderFlag,
    offset: u64,
    virtual_addr: u64,
    physical_addr: u64,
    file_size: u64,
    memory_size: u64,
    alignment: u64,
};

pub const MAGIC = 0x464C457F;
