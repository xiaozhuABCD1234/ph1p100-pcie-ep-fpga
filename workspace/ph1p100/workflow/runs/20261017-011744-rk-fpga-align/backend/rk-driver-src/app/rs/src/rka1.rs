// SPDX-License-Identifier: GPL-2.0
//! T07：RKA1 安全扩展的用户态配套（与 `include/anlogic_pci_ioctl.h` 里
//! `struct anlogic_ioc_rka1` / `ANLOGIC_IOCRKA1` 一一对应）。
//!
//! 两块内容：
//!   1) [`Rka1`]：扩展探测 / 授权配置 / one-shot ARM / ACK_RELEASE / CANCEL 的薄封装。
//!      所有操作都 fail closed：EXT_MAGIC != "RKA1" 时直接报错，**不退回旧行为**。
//!   2) [`r10f`]：R10F 非压缩帧的严格解析（magic/version/format/codec/几何/三层长度/
//!      三段 CRC/尾零），任何一项不符就拒绝，绝不「夹紧后当成功」。
//!
//! 说明：本模块不改任何既有结构体布局与 ioctl 编号；新结构体只走新编号 15。

use crate::ioctl::*;
use crate::sys;

/// `struct anlogic_ioc_rka1`（与内核头文件逐字段对应）
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct IocRka1 {
    pub op: u32,
    pub cap_bytes: u32,
    pub session: u32,
    pub ack_seq: u32,
    pub ack_session: u32,
    pub ext_magic: u32,
    pub ext_version: u32,
    pub tx_status: u32,
    pub push_err: u32,
    pub push_status: u32,
    pub push_done: u32,
    pub armed: u32,
    pub held: u32,
    pub busy: u32,
    pub rejected: u32,
}

pub const RKA1_OP_PROBE: u32 = 0;
pub const RKA1_OP_CONFIGURE: u32 = 1;
pub const RKA1_OP_ARM: u32 = 2;
pub const RKA1_OP_ACK: u32 = 3;
pub const RKA1_OP_CANCEL: u32 = 4;

pub const RKA1_EXT_MAGIC: u32 = 0x3141_4B52; // "RKA1"（小端）
pub const RKA1_EXT_VERSION_MAJOR: u32 = 1;

pub const RKA1_ST_ARMED: u32 = 0x01;
pub const RKA1_ST_BUSY: u32 = 0x02;
pub const RKA1_ST_HELD: u32 = 0x04;
pub const RKA1_ST_REJECT: u32 = 0x08;
pub const RKA1_ST_DRAINING: u32 = 0x10;

/// `_IOWR('x', 15, struct anlogic_ioc_rka1)`（与头文件一致；Rust 侧按 ABI 重算）
pub const ANLOGIC_IOCRKA1: u64 = iowr(15, core::mem::size_of::<IocRka1>() as u32);

const fn iowr(nr: u32, size: u32) -> u64 {
    ((3u64) << 30) | ((size as u64) << 16) | ((ANLOGIC_IOC_MAGIC as u64) << 8) | (nr as u64)
}

pub struct Rka1 {
    fd: i32,
}

impl Rka1 {
    pub fn new(fd: i32) -> Self {
        Rka1 { fd }
    }

    fn call(&self, rq: &mut IocRka1) -> Result<(), (i32, String)> {
        let rv = unsafe { sys::ioctl(self.fd, ANLOGIC_IOCRKA1, rq as *mut IocRka1) };
        if rv < 0 {
            let err = sys::errno();
            return Err((err, describe(rq, err)));
        }
        Ok(())
    }

    /// 探测：EXT_MAGIC/EXT_VERSION 必须对。失败 = 该 FPGA 映像没有安全扩展。
    pub fn probe(&self) -> Result<IocRka1, (i32, String)> {
        let mut rq = IocRka1 { op: RKA1_OP_PROBE, ..Default::default() };
        self.call(&mut rq)?;
        if rq.ext_magic != RKA1_EXT_MAGIC {
            return Err((
                libc_einval(),
                format!(
                    "EXT_MAGIC=0x{:08x} != 0x{:08x}（旧映像）：拒绝进入安全模式",
                    rq.ext_magic, RKA1_EXT_MAGIC
                ),
            ));
        }
        if (rq.ext_version >> 16) != RKA1_EXT_VERSION_MAJOR {
            return Err((
                libc_einval(),
                format!("EXT_VERSION=0x{:08x} 主版本不符", rq.ext_version),
            ));
        }
        Ok(rq)
    }

    pub fn configure(&self, cap_bytes: u32, session: u32) -> Result<IocRka1, (i32, String)> {
        let mut rq = IocRka1 {
            op: RKA1_OP_CONFIGURE,
            cap_bytes,
            session,
            ..Default::default()
        };
        self.call(&mut rq)?;
        Ok(rq)
    }

    pub fn arm(&self) -> Result<IocRka1, (i32, String)> {
        let mut rq = IocRka1 { op: RKA1_OP_ARM, ..Default::default() };
        self.call(&mut rq)?;
        if rq.armed == 0 {
            return Err((libc_einval(), format!("ARM 后 TX_STATUS=0x{:08x} 未置 armed", rq.tx_status)));
        }
        Ok(rq)
    }

    pub fn ack(&self, seq: u32, session: u32) -> Result<IocRka1, (i32, String)> {
        let mut rq = IocRka1 {
            op: RKA1_OP_ACK,
            ack_seq: seq,
            ack_session: session,
            ..Default::default()
        };
        self.call(&mut rq)?;
        if rq.held != 0 {
            return Err((libc_einval(), format!("ACK 后仍 held（TX_STATUS=0x{:08x}）", rq.tx_status)));
        }
        Ok(rq)
    }

    pub fn cancel(&self) -> Result<IocRka1, (i32, String)> {
        let mut rq = IocRka1 { op: RKA1_OP_CANCEL, ..Default::default() };
        self.call(&mut rq)?;
        Ok(rq)
    }
}

fn libc_einval() -> i32 {
    22
}

fn describe(rq: &IocRka1, err: i32) -> String {
    format!(
        "RKA1 ioctl(op={}) 失败 errno={}（TX_STATUS=0x{:08x}，0xC8={}）",
        rq.op, err, rq.tx_status, rq.push_err
    )
}

/// R10F 非压缩帧的严格解析（T07）。
///
/// 判据（任一项不符即 `Err`，不做任何"夹紧/容错"）：
///   · magic == 0x46523052（"R0FR" 小端，见 frame_contract.py）、version == 0、
///     format == 0（非压缩）、codec == 0（RAW，BPR1 是另一个 codec，不在这里）、
///     valid_bits == 10、packing == 0；
///   · width/height/stride 与传输长度自洽：stride >= ceil(width*10/8)，
///     raw_bytes == payload_bytes == stride*height（本框架无额外行填充）；
///   · dma_len 必须精确等于 hdr(128) + payload + 尾零，且尾零全 0；
///   · header_crc32 / payload_crc32 与内容逐字节相符（IEEE 反射 poly 0xEDB88320，
///     init/final 全 1；header CRC 计算时把 0x58..0x5B 的 crc 字段自身清 0）。
pub mod r10f {
    pub const MAGIC: u32 = 0x52_30_46_52; // 'R','0','F','R'（小端）
    pub const HDR_BYTES: usize = 128;
    pub const VALID_BITS: u16 = 10;

    #[derive(Debug, Clone, Copy)]
    pub struct R10fHeader {
        pub version: u16,
        pub format: u16,
        pub codec: u16,
        pub valid_bits: u16,
        pub packing: u16,
        pub flags: u32,
        pub width: u16,
        pub height: u16,
        pub stride: u32,
        pub raw_bytes: u32,
        pub payload_bytes: u32,
        pub header_crc32: u32,
        pub payload_crc32: u32,
        pub session: u32,
        pub seq: u32,
    }

    pub fn le16(b: &[u8], o: usize) -> u16 {
        u16::from_le_bytes([b[o], b[o + 1]])
    }
    pub fn le32(b: &[u8], o: usize) -> u32 {
        u32::from_le_bytes([b[o], b[o + 1], b[o + 2], b[o + 3]])
    }

    pub fn crc32_ieee(data: &[u8]) -> u32 {
        let mut crc: u32 = 0xffff_ffff;
        for &byte in data {
            crc ^= byte as u32;
            for _ in 0..8 {
                let lsb = crc & 1;
                crc >>= 1;
                if lsb != 0 {
                    crc ^= 0xEDB8_8320;
                }
            }
        }
        !crc
    }

    pub fn parse(hdr: &[u8], payload: &[u8], transport_tail: &[u8], expect_w: u16, expect_h: u16, expect_session: Option<u32>)
        -> Result<R10fHeader, String>
    {
        if hdr.len() < HDR_BYTES {
            return Err(format!("header too short: {} < {}", hdr.len(), HDR_BYTES));
        }
        if le32(hdr, 0) != MAGIC {
            return Err(format!("bad R10F magic 0x{:08x}", le32(hdr, 0)));
        }
        let h = R10fHeader {
            version: le16(hdr, 4),
            format: le16(hdr, 6),
            codec: le16(hdr, 8),
            valid_bits: le16(hdr, 10),
            packing: le16(hdr, 12),
            flags: le32(hdr, 16),
            width: le16(hdr, 24),
            height: le16(hdr, 26),
            stride: le32(hdr, 28),
            raw_bytes: le32(hdr, 32),
            payload_bytes: le32(hdr, 36),
            header_crc32: le32(hdr, 0x58),
            payload_crc32: le32(hdr, 0x5c),
            session: le32(hdr, 0x60),
            seq: le32(hdr, 0x64),
        };
        if h.version != 0 {
            return Err(format!("R10F version {} != 0", h.version));
        }
        if h.format != 0 {
            return Err(format!("R10F format {} != 0（非压缩）", h.format));
        }
        if h.codec != 0 {
            return Err(format!("R10F codec {} 未知（BPR1 走别的 codec）", h.codec));
        }
        if h.valid_bits != VALID_BITS || h.packing != 0 {
            return Err(format!(
                "R10F valid_bits={} / packing={}（本框架只支持 10bit packed）",
                h.valid_bits, h.packing
            ));
        }
        if h.width != expect_w || h.height != expect_h {
            return Err(format!(
                "R10F geometry {}x{} != 已授权的 {}x{}",
                h.width, h.height, expect_w, expect_h
            ));
        }
        let min_stride = ((h.width as u32) * 10 + 7) / 8;
        if h.stride < min_stride {
            return Err(format!("R10F stride {} < 每行最少 {} ", h.stride, min_stride));
        }
        if h.raw_bytes != h.payload_bytes {
            return Err(format!(
                "R10F raw_bytes {} != payload_bytes {}",
                h.raw_bytes, h.payload_bytes
            ));
        }
        if h.payload_bytes != h.stride * h.height as u32 {
            return Err(format!(
                "R10F payload {} != stride {} * height {}",
                h.payload_bytes, h.stride, h.height
            ));
        }
        if payload.len() != h.payload_bytes as usize {
            return Err(format!(
                "payload len {} != payload_bytes {}",
                payload.len(), h.payload_bytes
            ));
        }
        if !transport_tail.iter().all(|b| *b == 0) {
            return Err("transport tail is not all zero".to_string());
        }
        if let Some(sess) = expect_session {
            if h.session != sess {
                return Err(format!("R10F session 0x{:08x} != 授权 session 0x{:08x}", h.session, sess));
            }
        }
        // header CRC：把自身 crc 字段清 0 再算
        let mut hdr_copy = [0u8; HDR_BYTES];
        hdr_copy.copy_from_slice(&hdr[..HDR_BYTES]);
        hdr_copy[0x58] = 0;
        hdr_copy[0x59] = 0;
        hdr_copy[0x5a] = 0;
        hdr_copy[0x5b] = 0;
        let hc = crc32_ieee(&hdr_copy);
        if hc != h.header_crc32 {
            return Err(format!("header_crc32 0x{:08x} != 计算值 0x{:08x}", h.header_crc32, hc));
        }
        let pc = crc32_ieee(payload);
        if pc != h.payload_crc32 {
            return Err(format!("payload_crc32 0x{:08x} != 计算值 0x{:08x}", h.payload_crc32, pc));
        }
        Ok(h)
    }
}
