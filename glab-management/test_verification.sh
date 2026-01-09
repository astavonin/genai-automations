#!/bin/bash

echo "=== Verification Tests for --group Removal ==="
echo ""

echo "1. Checking that --group is not in help output..."
if python3 glab_tasks_management.py --help 2>&1 | grep -q -- "--group"; then
    echo "   ❌ FAILED: --group found in main help"
    exit 1
else
    echo "   ✅ PASSED: --group not in main help"
fi

echo ""
echo "2. Checking create subcommand help..."
if python3 glab_tasks_management.py create --help 2>&1 | grep -q -- "--group"; then
    echo "   ❌ FAILED: --group found in create help"
    exit 1
else
    echo "   ✅ PASSED: --group not in create help"
fi

echo ""
echo "3. Checking load subcommand help..."
if python3 glab_tasks_management.py load --help 2>&1 | grep -q -- "--group"; then
    echo "   ❌ FAILED: --group found in load help"
    exit 1
else
    echo "   ✅ PASSED: --group not in load help"
fi

echo ""
echo "4. Checking search subcommand help..."
if python3 glab_tasks_management.py search --help 2>&1 | grep -q -- "--group"; then
    echo "   ❌ FAILED: --group found in search help"
    exit 1
else
    echo "   ✅ PASSED: --group not in search help"
fi

echo ""
echo "5. Checking that --group flag is rejected..."
if python3 glab_tasks_management.py create --group test dummy.yaml 2>&1 | grep -q "unrecognized arguments"; then
    echo "   ✅ PASSED: --group flag correctly rejected"
else
    echo "   ❌ FAILED: --group flag should be rejected"
    exit 1
fi

echo ""
echo "=== All Verification Tests Passed ==="
