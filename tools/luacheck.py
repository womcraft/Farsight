#!/usr/bin/env python3
"""Minimal Lua 5.1 syntax checker + global-usage lister (no Lua runtime needed).
Usage: luacheck.py file.lua [file.lua ...]   -> prints syntax errors and the globals each file reads/writes."""
import re, sys

KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local",
            "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"}
TOKEN = re.compile(r"""
    (?P<ws>\s+)
  | (?P<lcomment>--\[(?P<ceq>=*)\[)
  | (?P<comment>--[^\n]*)
  | (?P<lstr>\[(?P<seq>=*)\[)
  | (?P<num>0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+(?:[eE][+-]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<str>"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')
  | (?P<op>\.\.\.|\.\.|==|~=|<=|>=|[-+*/%^\#<>=(){}\[\];:,.])
""", re.X | re.S)


class LuaError(Exception):
    pass


def tokenize(src):
    toks, i, line = [], 0, 1
    while i < len(src):
        m = TOKEN.match(src, i)
        if not m:
            raise LuaError("line %d: unexpected character %r" % (line, src[i]))
        kind = m.lastgroup
        text = m.group(0)
        if kind in ("lcomment", "lstr"):
            eq = m.group("ceq") if kind == "lcomment" else m.group("seq")
            close = "]" + eq + "]"
            j = src.find(close, m.end())
            if j < 0:
                raise LuaError("line %d: unfinished long string/comment" % line)
            text = src[i:j + len(close)]
            if kind == "lstr":
                toks.append(("str", text, line))
            line += text.count("\n")
            i = j + len(close)
            continue
        if kind == "name":
            toks.append(("kw" if text in KEYWORDS else "name", text, line))
        elif kind in ("num", "str", "op"):
            toks.append((kind, text, line))
        line += text.count("\n")
        i = m.end()
    toks.append(("eof", "<eof>", line))
    return toks


BINOPS = {"or": 1, "and": 2, "<": 3, ">": 3, "<=": 3, ">=": 3, "~=": 3, "==": 3, "..": 4, "+": 5, "-": 5,
          "*": 6, "/": 6, "%": 6, "^": 8}


class Parser:
    def __init__(self, src):
        self.t = tokenize(src)
        self.p = 0
        self.scopes = [set()]
        self.gread, self.gwrite = {}, {}

    # --- helpers
    def peek(self):
        return self.t[self.p]

    def nxt(self):
        tok = self.t[self.p]
        self.p += 1
        return tok

    def check(self, text):
        k, v, _ = self.peek()
        return v == text and k in ("kw", "op")

    def accept(self, text):
        if self.check(text):
            self.p += 1
            return True
        return False

    def expect(self, text):
        if not self.accept(text):
            k, v, ln = self.peek()
            raise LuaError("line %d: expected '%s' near '%s'" % (ln, text, v))

    def name(self):
        k, v, ln = self.nxt()
        if k != "name":
            raise LuaError("line %d: expected a name near '%s'" % (ln, v))
        return v

    def declare(self, n):
        self.scopes[-1].add(n)

    def use(self, n, ln, write=False):
        for s in reversed(self.scopes):
            if n in s:
                return
        (self.gwrite if write else self.gread).setdefault(n, ln)

    # --- grammar
    def block(self, new_scope=True, pre=()):
        if new_scope:
            self.scopes.append(set(pre))
        while True:
            k, v, ln = self.peek()
            if k == "eof" or (k == "kw" and v in ("end", "else", "elseif", "until")):
                break
            if k == "kw" and v == "return":
                self.nxt()
                k2, v2, _ = self.peek()
                if not (k2 == "eof" or (k2 == "kw" and v2 in ("end", "else", "elseif", "until")) or v2 == ";"):
                    self.exprlist()
                self.accept(";")
                break
            if k == "kw" and v == "break":
                self.nxt()
                self.accept(";")
                break
            self.statement()
            self.accept(";")
        if new_scope:
            self.scopes.pop()

    def statement(self):
        k, v, ln = self.peek()
        if k == "kw":
            if v == "if":
                self.nxt(); self.expr(); self.expect("then"); self.block()
                while self.accept("elseif"):
                    self.expr(); self.expect("then"); self.block()
                if self.accept("else"):
                    self.block()
                self.expect("end"); return
            if v == "while":
                self.nxt(); self.expr(); self.expect("do"); self.block(); self.expect("end"); return
            if v == "do":
                self.nxt(); self.block(); self.expect("end"); return
            if v == "for":
                self.nxt()
                names = [self.name()]
                if self.accept("="):
                    self.expr(); self.expect(","); self.expr()
                    if self.accept(","):
                        self.expr()
                else:
                    while self.accept(","):
                        names.append(self.name())
                    self.expect("in"); self.exprlist()
                self.expect("do"); self.block(pre=names); self.expect("end"); return
            if v == "repeat":
                self.nxt()
                self.scopes.append(set())
                self.block(new_scope=False)
                self.expect("until"); self.expr()
                self.scopes.pop(); return
            if v == "function":
                self.nxt()
                k1, n1, l1 = self.nxt()
                if k1 != "name":
                    raise LuaError("line %d: expected function name" % l1)
                is_method, simple = False, True
                while self.check(".") or self.check(":"):
                    simple = False
                    if self.nxt()[1] == ":":
                        is_method = True
                        self.name(); break
                    self.name()
                self.use(n1, l1, write=simple)
                self.funcbody(is_method); return
            if v == "local":
                self.nxt()
                if self.accept("function"):
                    n = self.name(); self.declare(n); self.funcbody(False); return
                names = [self.name()]
                while self.accept(","):
                    names.append(self.name())
                if self.accept("="):
                    self.exprlist()
                for n in names:
                    self.declare(n)
                return
            raise LuaError("line %d: unexpected '%s'" % (ln, v))
        # expression statement: call or assignment
        kind, info = self.suffixedexp()
        if self.check("=") or self.check(","):
            targets = [(kind, info)]
            while self.accept(","):
                targets.append(self.suffixedexp())
            self.expect("=")
            self.exprlist()
            for tk, ti in targets:
                if tk == "call":
                    raise LuaError("line %d: cannot assign to a function call" % ln)
                if tk == "name":
                    # was recorded as a read; move to writes
                    n, l = ti
                    if n in self.gread and self.gread[n] == l:
                        del self.gread[n]
                    self.use(n, l, write=True)
        elif kind != "call":
            raise LuaError("line %d: syntax error near '%s' (statement is not a call or assignment)" % (ln, self.peek()[1]))

    def funcbody(self, is_method):
        self.expect("(")
        params = ["self"] if is_method else []
        if not self.check(")"):
            while True:
                if self.accept("..."):
                    break
                params.append(self.name())
                if not self.accept(","):
                    break
        self.expect(")")
        self.block(pre=params)
        self.expect("end")

    def exprlist(self):
        self.expr()
        while self.accept(","):
            self.expr()

    def primaryexp(self):
        k, v, ln = self.nxt()
        if k == "name":
            self.use(v, ln)
            return "name", (v, ln)
        if v == "(" and k == "op":
            self.expr(); self.expect(")")
            return "paren", None
        raise LuaError("line %d: unexpected symbol near '%s'" % (ln, v))

    def suffixedexp(self):
        kind, info = self.primaryexp()
        while True:
            k, v, ln = self.peek()
            if k == "op" and v == ".":
                self.nxt(); self.name(); kind = "index"
            elif k == "op" and v == "[":
                self.nxt(); self.expr(); self.expect("]"); kind = "index"
            elif k == "op" and v == ":":
                self.nxt(); self.name(); self.callargs(); kind = "call"
            elif (k == "op" and v in ("(", "{")) or k == "str":
                self.callargs(); kind = "call"
            else:
                return kind, info

    def callargs(self):
        k, v, ln = self.peek()
        if k == "str":
            self.nxt()
        elif v == "{":
            self.table()
        else:
            self.expect("(")
            if not self.check(")"):
                self.exprlist()
            self.expect(")")

    def table(self):
        self.expect("{")
        while not self.check("}"):
            k, v, ln = self.peek()
            if k == "op" and v == "[":
                self.nxt(); self.expr(); self.expect("]"); self.expect("="); self.expr()
            elif k == "name" and self.t[self.p + 1][1] == "=" and self.t[self.p + 1][0] == "op":
                self.nxt(); self.nxt(); self.expr()
            else:
                self.expr()
            if not (self.accept(",") or self.accept(";")):
                break
        self.expect("}")

    def simpleexp(self):
        k, v, ln = self.peek()
        if k in ("num", "str"):
            self.nxt(); return
        if k == "kw" and v in ("nil", "true", "false"):
            self.nxt(); return
        if k == "op" and v == "...":
            self.nxt(); return
        if k == "op" and v == "{":
            self.table(); return
        if k == "kw" and v == "function":
            self.nxt(); self.funcbody(False); return
        self.suffixedexp()

    def expr(self, limit=0):
        k, v, ln = self.peek()
        if (k == "kw" and v == "not") or (k == "op" and v in ("-", "#")):
            self.nxt(); self.expr(7)
        else:
            self.simpleexp()
        while True:
            k, v, ln = self.peek()
            if k not in ("kw", "op") or v not in BINOPS or BINOPS[v] <= limit:
                break
            self.nxt()
            pr = BINOPS[v]
            self.expr(pr - 1 if v in ("..", "^") else pr)

    def parse(self):
        self.block(new_scope=False)
        k, v, ln = self.peek()
        if k != "eof":
            raise LuaError("line %d: unexpected '%s'" % (ln, v))


def main(files):
    bad = 0
    allr, allw = {}, {}
    for fn in files:
        src = open(fn, encoding="utf8").read()
        if src.startswith("﻿"):
            src = src[1:]
        p = Parser(src)
        try:
            p.parse()
        except LuaError as e:
            bad += 1
            print("SYNTAX ERROR %s: %s" % (fn, e))
            continue
        print("ok  %s  (%d lines)" % (fn, src.count("\n") + 1))
        for n, l in p.gread.items():
            allr.setdefault(n, "%s:%d" % (fn.split("/")[-1], l))
        for n, l in p.gwrite.items():
            allw.setdefault(n, "%s:%d" % (fn.split("/")[-1], l))
    print("\nGLOBALS WRITTEN: " + ", ".join("%s (%s)" % kv for kv in sorted(allw.items())))
    print("\nGLOBALS READ: " + " ".join(sorted(n for n in allr if n not in allw)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
