/* emb_libc.c — string funcs some Embench kernels need beyond the CoreMark
 * libc.c subset (which already provides mem-funcs, strlen, strcpy, strcmp, etc).
 * No overlap with libc.c. SPDX-License-Identifier: GPL-3.0-or-later */
#include <stddef.h>

/* newlib's wrapped sqrt() (wikisort) references errno via __errno(); bare-metal,
   single-thread, so a static cell suffices. */
int *
__errno (void)
{
  static int _e;
  return &_e;
}

char *
strchr (const char *s, int c)
{
  while (*s)
    {
      if (*s == (char) c)
	return (char *) s;
      s++;
    }
  return (c == 0) ? (char *) s : NULL;
}

char *
strrchr (const char *s, int c)
{
  const char *r = NULL;
  do
    {
      if (*s == (char) c)
	r = s;
    }
  while (*s++);
  return (char *) r;
}

int
strncmp (const char *a, const char *b, size_t n)
{
  for (; n--; a++, b++)
    {
      if (*a != *b)
	return (unsigned char) *a - (unsigned char) *b;
      if (!*a)
	break;
    }
  return 0;
}

void *
memchr (const void *s, int c, size_t n)
{
  const unsigned char *p = s;
  while (n--)
    {
      if (*p == (unsigned char) c)
	return (void *) p;
      p++;
    }
  return NULL;
}
