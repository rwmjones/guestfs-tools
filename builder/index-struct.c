/* libguestfs virt-builder tool
 * Copyright (C) 2013 Red Hat Inc.
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
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 */

#include <config.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "index-struct.h"

static void free_section (struct section *section);
static void free_field (struct field *field);

void
parse_context_init (struct parse_context *context)
{
  memset (context, 0, sizeof *context);
}

void
parse_context_free (struct parse_context *context)
{
  free_section (context->parsed_index);
}

static void
free_section (struct section *section)
{
  if (section) {
    free_section (section->next);
    free (section->name);
    free_field (section->fields);
    free (section);
  }
}

static void
free_field (struct field *field)
{
  if (field) {
    free_field (field->next);
    free (field->key);
    free (field->subkey);
    free (field->value);
    free (field);
  }
}
