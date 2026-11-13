"""Verify publication gates after removing the demo database dependency."""
from itertools import product
from functools import lru_cache
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ActionsCondition:
    """Evaluate the boolean subset used by the actual workflow conditions.

    This deliberately has no eval(), shell execution, or expression rewriting.
    Unknown syntax fails the test instead of silently approximating Actions.
    """

    TOKEN = re.compile(r"\s*(?:(\&\&|\|\||==|!=|[!(),])|('(?:[^']|'')*')|([A-Za-z_][\w.-]*))")
    STATUS_FUNCTIONS = frozenset({"always", "cancelled", "success", "failure"})

    def __init__(self, expression, context):
        expression = expression.strip()
        if expression.startswith("${{") and expression.endswith("}}"):
            expression = expression[3:-2].strip()
        self.tokens = []
        cursor = 0
        while cursor < len(expression):
            match = self.TOKEN.match(expression, cursor)
            if match is None:
                raise AssertionError(f"Unsupported workflow condition at offset {cursor}")
            self.tokens.append(next(value for value in match.groups() if value is not None))
            cursor = match.end()
        self.index = 0
        self.context = context
        self.calls = set()

    def take(self, token):
        if self.index < len(self.tokens) and self.tokens[self.index] == token:
            self.index += 1
            return True
        return False

    def evaluate(self):
        value = self.parse_or()
        if self.index != len(self.tokens):
            raise AssertionError("Unexpected trailing workflow condition tokens")
        return bool(value)

    def parse_or(self):
        value = self.parse_and()
        while self.take("||"):
            # Parse both sides even when one short-circuits, so unsupported
            # syntax or a changed dependency cannot hide in another branch.
            right = self.parse_and()
            value = bool(value) or bool(right)
        return value

    def parse_and(self):
        value = self.parse_equality()
        while self.take("&&"):
            right = self.parse_equality()
            value = bool(value) and bool(right)
        return value

    def parse_equality(self):
        value = self.parse_unary()
        while self.index < len(self.tokens) and self.tokens[self.index] in {"==", "!="}:
            operator = self.tokens[self.index]
            self.index += 1
            right = self.parse_unary()
            if isinstance(value, str) and isinstance(right, str):
                equal = value.casefold() == right.casefold()
            else:
                equal = value == right
            value = equal if operator == "==" else not equal
        return value

    def parse_unary(self):
        if self.take("!"):
            return not bool(self.parse_unary())
        if self.take("("):
            value = self.parse_or()
            if not self.take(")"):
                raise AssertionError("Unclosed workflow condition")
            return value
        if self.index >= len(self.tokens):
            raise AssertionError("Missing workflow condition value")
        token = self.tokens[self.index]
        self.index += 1
        if token.startswith("'"):
            return token[1:-1].replace("''", "'")
        if self.take("("):
            arguments = []
            if not self.take(")"):
                arguments.append(self.parse_or())
                while self.take(","):
                    arguments.append(self.parse_or())
                if not self.take(")"):
                    raise AssertionError("Unclosed workflow condition function")
            self.calls.add(token)
            if token == "startsWith" and len(arguments) == 2:
                return str(arguments[0]).casefold().startswith(str(arguments[1]).casefold())
            if token in self.STATUS_FUNCTIONS and not arguments:
                return self.context[token]
            raise AssertionError(f"Unsupported workflow condition function: {token}")
        if token == "true":
            return True
        if token == "false":
            return False
        if not token.startswith(("github.", "needs.")):
            raise AssertionError(f"Unsupported workflow condition property: {token}")
        # Missing outputs are the empty string in Actions, not boolean false.
        return self.context.get(token, "")



@lru_cache(maxsize=None)
def build_job(name):
    source = (ROOT / '.github/workflows/build.yml').read_text(encoding='utf-8')
    match = re.search(r'^  ' + re.escape(name) + r':\n(.*?)(?=^  [a-zA-Z][\w-]*:|\Z)', source, re.M | re.S)
    if match is None:
        raise AssertionError('Missing build job: ' + name)
    return match[1]


def condition(name, event='push', ref='refs/heads/main', results=None, cancelled=False):
    job = build_job(name)
    match = re.search(r'^    if: >-\n((?:      .*\n)+)', job, re.M)
    if match is None:
        raise AssertionError('Missing publication condition')
    results = results or dict.fromkeys(('check', 'web', 'android', 'ios'), 'success')
    context = {'github.event_name': event, 'github.ref': ref,
               'always': True, 'cancelled': cancelled,
               'success': all(value == 'success' for value in results.values()),
               'failure': any(value == 'failure' for value in results.values())}
    context.update({'needs.' + key + '.result': value for key, value in results.items()})
    return ActionsCondition(match[1], context).evaluate()


class BuildWorkflowTests(unittest.TestCase):
    def test_native_preview_builds_wire_and_verify_email_test_code(self):
        for name in ('android', 'ios'):
            job = build_job(name)
            self.assertIn('--dart-define=SAFE_WALK_EMAIL_LIVE_TEST=true', job)
            self.assertIn('--email-live-test', job)
        self.assertNotIn('SAFE_WALK_EMAIL_LIVE_TEST', build_job('web'))
        self.assertIn('--dart-define=SAFE_WALK_EMAIL_LIVE_TEST=true', build_job('check'))

    def test_publication_depends_on_all_checks_and_platforms(self):
        for name in ('publish', 'pages-settings'):
            self.assertIn('needs: [check, web, android, ios]', build_job(name))
            for statuses in product(('success', 'failure', 'cancelled', 'skipped'), repeat=4):
                with self.subTest(job=name, statuses=statuses):
                    results = dict(zip(('check', 'web', 'android', 'ios'), statuses))
                    self.assertEqual(condition(name, results=results), all(s == 'success' for s in statuses))

    def test_event_ref_and_cancellation_boundaries(self):
        for name in ('publish', 'pages-settings'):
            self.assertTrue(condition(name))
            self.assertFalse(condition(name, event='pull_request', ref='refs/pull/1/merge'))
            self.assertFalse(condition(name, ref='refs/heads/feature'))
            self.assertFalse(condition(name, cancelled=True))
        self.assertTrue(condition('publish', ref='refs/tags/v0.0.12-pre.1'))
        self.assertFalse(condition('publish', event='workflow_dispatch'))
        self.assertTrue(condition('pages-settings', event='workflow_dispatch'))
        self.assertFalse(condition('pages-settings', ref='refs/tags/v0.0.12-pre.1'))

    def test_workflows_never_run_demo_database_operations(self):
        for file in (ROOT / '.github/workflows').glob('*.yml'):
            source = file.read_text(encoding='utf-8')
            with self.subTest(workflow=file.name):
                self.assertNotRegex(source, r'demo[-_]database|DEMO_DATABASE|supabase/demo|reset_demo')
                self.assertIn('check_crime_database_isolation.py', source)



class SafeWalkConcurrencyTests(unittest.TestCase):
    def test_pushes_keep_independent_runs_and_pr_updates_can_cancel(self):
        source = (ROOT / '.github/workflows/safe_walk.yml').read_text(encoding='utf-8')
        block = source.split('\nconcurrency:', 1)[1].split('\ndefaults:', 1)[0]
        group = re.search(r'^  group: (.+)$', block, re.M).group(1)
        cancel = re.search(r'^  cancel-in-progress: (.+)$', block, re.M).group(1)
        self.assertIn("github.event_name == 'pull_request' && github.ref || github.run_id", group)
        for event, expected in [('push', False), ('workflow_dispatch', False), ('pull_request', True)]:
            with self.subTest(event=event):
                self.assertEqual(ActionsCondition(cancel, {'github.event_name': event}).evaluate(), expected)

if __name__ == '__main__':
    unittest.main()
