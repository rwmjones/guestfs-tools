(* virt-sysprep
 * Copyright (C) 2012 Fujitsu Limited.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *)

open Sysprep_operation
open Common_gettext.Gettext

module G = Guestfs

let abrt_data_perform ~debug ~quiet g root side_effects =
  let typ = g#inspect_get_type root in
  if typ <> "windows" then (
    let paths = g#glob_expand "/var/spool/abrt/*" in
    Array.iter (
      fun path -> g#rm_rf path;
    ) paths
  )

let op = {
  defaults with
    name = "abrt-data";
    enabled_by_default = true;
    heading = s_"Remove the crash data generated by ABRT";
    pod_description = Some (s_"\
Remove the automatically generated ABRT crash data in
C</var/spool/abrt/>.");
    perform_on_filesystems = Some abrt_data_perform;
}

let () = register_operation op
