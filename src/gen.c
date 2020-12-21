#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "check.h"
#include "expr.h"
#include "gen.h"
#include "identifier.h"
#include "qbe.h"
#include "scope.h"
#include "trace.h"
#include "types.h"

static char *
ident_to_sym(const struct identifier *ident)
{
	if (ident->ns) {
		char *ns = ident_to_sym(ident->ns);
		if (!ns) {
			return NULL;
		}
		int n = snprintf(NULL, 0, "%s.%s", ns, ident->name);
		char *str = calloc(1, n + 1);
		assert(str);
		snprintf(str, n + 1, "%s.%s", ns, ident->name);
		free(ns);
		return str;
	}
	return strdup(ident->name);
}

static void
gen_temp(struct gen_context *ctx, struct qbe_value *val,
		const struct qbe_type *type, char *fmt)
{
	val->kind = QV_TEMPORARY;
	val->type = type;

	int n = snprintf(NULL, 0, fmt, ctx->id);
	char *str = calloc(1, n + 1);
	snprintf(str, n + 1, fmt, ctx->id);
	++ctx->id;

	val->name = str;
}

static void
alloc_temp(struct gen_context *ctx, struct qbe_value *val,
		const struct type *type, char *fmt)
{
	gen_temp(ctx, val, &qbe_long, fmt); // XXX: Architecture dependent

	struct qbe_value size;
	constl(&size, type->size);
	pushi(ctx->current, val, alloc_for_align(type->align), &size, NULL);
}

// Given value src of type A, and value dest of type pointer to A, store src in
// dest.
static void
gen_store(struct gen_context *ctx,
	const struct qbe_value *dest,
	const struct qbe_value *src)
{
	const struct qbe_type *qtype = src->type;
	assert(qtype->stype != Q__VOID); // Invariant
	assert(qtype->stype != Q__AGGREGATE); // TODO
	pushi(ctx->current, NULL, store_for_type(qtype->stype), src, dest, NULL);
}

// Given value src of type pointer to A, and value dest of type A, load dest
// from src.
static void
gen_load(struct gen_context *ctx,
	const struct qbe_value *dest,
	const struct qbe_value *src,
	bool is_signed)
{
	const struct qbe_type *qtype = dest->type;
	assert(qtype->stype != Q__VOID); // Invariant
	assert(qtype->stype != Q__AGGREGATE); // TODO
	pushi(ctx->current, dest,
		load_for_type(qtype->stype, is_signed), src, NULL);
}

// Same as gen_load but dest is initialized to a new temporary
static void
gen_loadtemp(struct gen_context *ctx,
		struct qbe_value *dest, const struct qbe_value *src,
		const struct qbe_type *type, bool is_signed)
{
	gen_temp(ctx, dest, type, "load.%d");
	gen_load(ctx, dest, src, is_signed);
}

static void gen_expression(struct gen_context *ctx,
	const struct expression *expr, const struct qbe_value *out);

static void
gen_constant(struct gen_context *ctx,
	const struct expression *expr,
	const struct qbe_value *out)
{
	if (out == NULL) {
		pushc(ctx->current, "useless constant expression discarded");
		return;
	}

	const struct qbe_type *qtype = qtype_for_type(ctx, expr->result, false);
	struct qbe_value val = {0};
	switch (qtype->stype) {
	case Q_BYTE:
	case Q_HALF:
	case Q_WORD:
		constw(&val, (uint32_t)expr->constant.uval);
		break;
	case Q_LONG:
		constl(&val, (uint64_t)expr->constant.uval);
		break;
	case Q_SINGLE:
		consts(&val, (float)expr->constant.fval);
		break;
	case Q_DOUBLE:
		constd(&val, expr->constant.fval);
		break;
	case Q__AGGREGATE:
		assert(0); // TODO: General-purpose store
	case Q__VOID:
		assert(0); // Invariant
	}

	gen_store(ctx, out, &val);
}

static void
gen_expr_list(struct gen_context *ctx,
	const struct expression *expr,
	const struct qbe_value *out)
{
	const struct expressions *exprs = &expr->list.exprs;
	while (exprs) {
		const struct qbe_value *dest = NULL;
		if (!exprs->next) {
			// Last value determines expression result
			dest = out;
		}
		gen_expression(ctx, exprs->expr, dest);
		exprs = exprs->next;
	}
}

static void
gen_expr_return(struct gen_context *ctx,
	const struct expression *expr,
	const struct qbe_value *out)
{
	if (expr->_return.value) {
		gen_expression(ctx, expr->_return.value, ctx->return_value);
	}
	pushi(ctx->current, NULL, Q_JMP, ctx->end_label, NULL);
}

static void
gen_expression(struct gen_context *ctx,
	const struct expression *expr,
	const struct qbe_value *out)
{
	switch (expr->type) {
	case EXPR_ACCESS:
	case EXPR_ASSERT:
	case EXPR_ASSIGN:
	case EXPR_BINARITHM:
	case EXPR_BINDING_LIST:
	case EXPR_BREAK:
	case EXPR_CALL:
	case EXPR_CAST:
		assert(0); // TODO
	case EXPR_CONSTANT:
		gen_constant(ctx, expr, out);
		break;
	case EXPR_CONTINUE:
	case EXPR_FOR:
	case EXPR_FREE:
	case EXPR_IF:
	case EXPR_INDEX:
		assert(0); // TODO
	case EXPR_LIST:
		gen_expr_list(ctx, expr, out);
		break;
	case EXPR_MATCH:
	case EXPR_MEASURE:
	case EXPR_RETURN:
		gen_expr_return(ctx, expr, out);
		break;
	case EXPR_SLICE:
	case EXPR_STRUCT:
	case EXPR_SWITCH:
	case EXPR_UNARITHM:
	case EXPR_WHILE:
		assert(0); // TODO
	}
}

static void
gen_function_decl(struct gen_context *ctx, const struct declaration *decl)
{
	assert(decl->type == DECL_FUNC);
	const struct function_decl *func = &decl->func;
	const struct type *fntype = func->type;
	assert(func->flags == 0); // TODO

	struct qbe_def *qdef = calloc(1, sizeof(struct qbe_def));
	qdef->type = Q_FUNC;
	qdef->exported = decl->exported;
	qdef->name = func->symbol ? strdup(func->symbol)
		: ident_to_sym(&decl->ident);
	qdef->func.returns = qtype_for_type(ctx, fntype->func.result, true);
	ctx->current = &qdef->func;

	pushl(&qdef->func, &ctx->id, "start.%d");

	struct qbe_func_param *param, **next = &qdef->func.params;
	struct scope_object *obj = decl->func.scope->objects;
	while (obj) {
		// TODO: Copy params to the stack (for non-aggregate types)
		param = *next = calloc(1, sizeof(struct qbe_func_param));
		assert(!obj->ident.ns); // Invariant
		param->name = strdup(obj->ident.name);
		param->type = qtype_for_type(ctx, obj->type, true);
		obj = obj->next;
		next = &param->next;
	}

	struct qbe_statement end_label = {0};
	struct qbe_value end_label_v = {
		.kind = QV_LABEL,
		.name = strdup(genl(&end_label, &ctx->id, "end.%d")),
	};
	ctx->end_label = &end_label_v;

	// TODO: Update for void type
	struct qbe_value rval;
	alloc_temp(ctx, &rval, fntype->func.result, "return.%d");
	ctx->return_value = &rval;

	pushl(&qdef->func, &ctx->id, "body.%d");
	gen_expression(ctx, func->body, &rval);
	push(&qdef->func, &end_label);

	struct qbe_value load;
	gen_loadtemp(ctx, &load, &rval, qdef->func.returns,
		type_is_signed(fntype->func.result));
	pushi(&qdef->func, NULL, Q_RET, &load, NULL);

	qbe_append_def(ctx->out, qdef);
	ctx->current = NULL;
}

static void
gen_decl(struct gen_context *ctx, const struct declaration *decl)
{
	switch (decl->type) {
	case DECL_FUNC:
		gen_function_decl(ctx, decl);
		break;
	case DECL_TYPE:
	case DECL_GLOBAL:
	case DECL_CONSTANT:
		assert(0); // TODO
	}
}

void
gen(const struct unit *unit, struct qbe_program *out)
{
	struct gen_context ctx = {
		.out = out,
		.ns = unit->ns,
	};
	const struct declarations *decls = unit->declarations;
	assert(decls); // At least one is required
	trenter(TR_GEN, "gen");
	while (decls) {
		gen_decl(&ctx, &decls->decl);
		decls = decls->next;
	}
	trleave(TR_GEN, NULL);
}
