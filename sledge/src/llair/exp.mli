(*
 * Copyright (c) 2018-present, Facebook, Inc.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

(** Expressions

    Pure (heap-independent) expressions are complex arithmetic,
    bitwise-logical, etc. operations over literal values and registers.

    Expressions are represented in curried form, where the only† recursive
    constructor is [App], which is an application of a function symbol to an
    argument. This is done to simplify the definition of 'subexpression' and
    make it explicit, which is a significant help for treating equality
    between expressions using congruence closure. The specific constructor
    functions indicate and check the expected arity of the function symbols.

    [†] [Struct_rec] is also a recursive constructor, but its values are
    treated as atomic since, as they are recursive, doing otherwise would
    require inductive reasoning. *)

type t = private
  | Var of {id: int; name: string}  (** Local variable / virtual register *)
  | Nondet of {msg: string}
      (** Anonymous local variable with arbitrary value, representing
          non-deterministic approximation of value described by [msg] *)
  | Label of {parent: string; name: string}
      (** Address of named code block within parent function *)
  | App of {op: t; arg: t}
      (** Application of function symbol to argument, curried *)
  | Null  (** Pointer value that never refers to an object *)
  | Splat  (** Iterated concatenation of a single byte *)
  | Memory  (** Size-tagged byte-array *)
  | Concat  (** Byte-array concatenation *)
  | Integer of {data: Z.t}  (** Integer constant *)
  | Float of {data: string}  (** Floating-point constant *)
  | Eq  (** Equal test *)
  | Dq  (** Disequal test *)
  | Gt  (** Greater-than test *)
  | Ge  (** Greater-than-or-equal test *)
  | Lt  (** Less-than test *)
  | Le  (** Less-than-or-equal test *)
  | Ugt  (** Unordered or greater-than test *)
  | Uge  (** Unordered or greater-than-or-equal test *)
  | Ult  (** Unordered or less-than test *)
  | Ule  (** Unordered or less-than-or-equal test *)
  | Ord  (** Ordered test (neither arg is nan) *)
  | Uno  (** Unordered test (some arg is nan) *)
  | Add  (** Addition *)
  | Sub  (** Subtraction *)
  | Mul  (** Multiplication *)
  | Div  (** Division *)
  | Udiv  (** Unsigned division *)
  | Rem  (** Remainder of division *)
  | Urem  (** Remainder of unsigned division *)
  | And  (** Conjunction *)
  | Or  (** Disjunction *)
  | Xor  (** Exclusive-or / Boolean disequality *)
  | Shl  (** Shift left *)
  | Lshr  (** Logical shift right *)
  | Ashr  (** Arithmetic shift right *)
  | Conditional  (** If-then-else *)
  | Record  (** Record (array / struct) constant *)
  | Select  (** Select an index from a record *)
  | Update  (** Constant record with updated index *)
  | Struct_rec of {elts: t vector}
      (** Struct constant that may recursively refer to itself
          (transitively) from [elts]. NOTE: represented by cyclic values. *)
  | Convert of {signed: bool; dst: Typ.t; src: Typ.t}
      (** Convert between specified types, possibly with loss of information *)
[@@deriving compare, hash, sexp]

type exp = t

include Comparator.S with type t := t

val equal : t -> t -> bool
val pp : t pp
val invariant : ?partial:bool -> t -> unit

(** Exp.Var is re-exported as Var *)
module Var : sig
  type t = private exp [@@deriving compare, hash, sexp]
  type var = t

  include Comparator.S with type t := t

  module Set : sig
    type t = (var, comparator_witness) Set.t [@@deriving compare, sexp]

    val pp : t pp
    val empty : t
    val of_vector : var vector -> t
  end

  val equal : t -> t -> bool
  val pp : t pp
  val pp_demangled : t pp

  include Invariant.S with type t := t

  val of_exp : exp -> t option
  val program : string -> t
  val fresh : string -> wrt:Set.t -> t * Set.t
  val id : t -> int
  val name : t -> string

  module Subst : sig
    type t [@@deriving compare, sexp]

    val pp : t pp
    val empty : t
    val freshen : Set.t -> wrt:Set.t -> t
    val extend : t -> replace:var -> with_:var -> t
    val invert : t -> t
    val exclude : t -> Set.t -> t
    val is_empty : t -> bool
    val domain : t -> Set.t
    val range : t -> Set.t
    val apply_set : t -> Set.t -> Set.t
    val close_set : t -> Set.t -> Set.t
  end
end

(** Construct *)

val var : Var.t -> t
val nondet : string -> t
val label : parent:string -> name:string -> t
val null : t
val splat : byt:t -> siz:t -> t
val memory : siz:t -> arr:t -> t
val concat : t -> t -> t
val bool : bool -> t
val integer : Z.t -> t
val float : string -> t
val eq : t -> t -> t
val dq : t -> t -> t
val gt : t -> t -> t
val ge : t -> t -> t
val lt : t -> t -> t
val le : t -> t -> t
val ugt : t -> t -> t
val uge : t -> t -> t
val ult : t -> t -> t
val ule : t -> t -> t
val ord : t -> t -> t
val uno : t -> t -> t
val add : t -> t -> t
val sub : t -> t -> t
val mul : t -> t -> t
val div : t -> t -> t
val udiv : t -> t -> t
val rem : t -> t -> t
val urem : t -> t -> t
val and_ : t -> t -> t
val or_ : t -> t -> t
val xor : t -> t -> t
val shl : t -> t -> t
val lshr : t -> t -> t
val ashr : t -> t -> t
val conditional : cnd:t -> thn:t -> els:t -> t
val record : t list -> t
val select : rcd:t -> idx:t -> t
val update : rcd:t -> elt:t -> idx:t -> t

val struct_rec :
     (module Hashtbl.Key with type t = 'id)
  -> (id:'id -> t lazy_t vector -> t) Staged.t
(** [struct_rec Id id element_thunks] constructs a possibly-cyclic [Struct]
    value. Cycles are detected using [Id]. The caller of [struct_rec Id]
    must ensure that a single unstaging of [struct_rec Id] is used for each
    complete cyclic value. Also, the caller must ensure that recursive calls
    to [struct_rec Id] provide [id] values that uniquely identify at least
    one point on each cycle. Failure to obey these requirements will lead to
    stack overflow. *)

val convert : ?signed:bool -> dst:Typ.t -> src:Typ.t -> t -> t

(** Access *)

val fold_vars : t -> init:'a -> f:('a -> Var.t -> 'a) -> 'a
val fold_exps : t -> init:'a -> f:('a -> t -> 'a) -> 'a
val fold : t -> init:'a -> f:('a -> t -> 'a) -> 'a
val fold_map : t -> init:'a -> f:('a -> t -> 'a * t) -> 'a * t
val map : t -> f:(t -> t) -> t

(** Update *)

val rename : t -> Var.Subst.t -> t

(** Query *)

val fv : t -> Var.Set.t
val is_true : t -> bool
val is_false : t -> bool
val is_constant : t -> bool
