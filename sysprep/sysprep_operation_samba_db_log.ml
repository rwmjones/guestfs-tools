(* virt-sysprep
 * Copyright (C) 2012 FUJITSU LIMITED
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
open Sysprep_gettext.Gettext

module G = Guestfs

let samba_db_log_perform g root =
  let typ = g#inspect_get_type root in
  if typ <> "windows" then (
    let paths = [ "/var/log/samba/old/*";
                  "/var/log/samba/*";
                  "/var/lib/samba/*/*";
                  "/var/lib/samba/*"; ] in
    List.iter (
      fun path ->
        let files = g#glob_expand path in
        Array.iter (
          fun file ->
            try g#rm file with G.Error _ -> ()
        ) files;
    ) paths;

    []
  )
  else []

let samba_db_log_op = {
  name = "samba-db-log";
  enabled_by_default = true;
  heading = s_"Remove the database and log files of Samba";
  pod_description = None;
  extra_args = [];
  perform_on_filesystems = Some samba_db_log_perform;
  perform_on_devices = None;
}

let () = register_operation samba_db_log_op
