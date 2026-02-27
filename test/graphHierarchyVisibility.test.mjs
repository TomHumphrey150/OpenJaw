import assert from 'node:assert/strict'
import test from 'node:test'

function parentIDsForNode(node) {
  if (!node) return []

  if (Array.isArray(node.parentIds)) {
    return node.parentIds
      .filter((value) => typeof value === 'string')
      .map((value) => value.trim())
      .filter((value) => value.length > 0)
  }

  if (typeof node.parentId === 'string' && node.parentId.length > 0) {
    return [node.parentId]
  }

  return []
}

function hierarchyMaps(nodes) {
  const parentsByID = new Map()

  nodes.forEach((node) => {
    if (!node || typeof node.id !== 'string') return
    const parentIDs = parentIDsForNode(node)
    if (parentIDs.length === 0) return
    parentsByID.set(node.id, parentIDs)
  })

  return { parentsByID }
}

function visibleNodeIDsByHierarchy(nodes, nodeByID, parentsByID) {
  const visibilityByID = new Map()
  const resolving = new Set()

  function isVisible(nodeID) {
    if (visibilityByID.has(nodeID)) {
      return visibilityByID.get(nodeID)
    }

    if (resolving.has(nodeID)) {
      return true
    }

    const node = nodeByID.get(nodeID)
    if (!node) {
      return false
    }

    resolving.add(nodeID)
    const parentIDs = parentsByID.get(nodeID) || []
    let visible = false

    if (parentIDs.length === 0) {
      visible = true
    } else {
      for (const parentID of parentIDs) {
        const parentNode = nodeByID.get(parentID)
        if (!parentNode) {
          visible = true
          break
        }

        if (!isVisible(parentID)) {
          continue
        }

        if (parentNode.isExpanded === false) {
          continue
        }

        visible = true
        break
      }
    }

    resolving.delete(nodeID)
    visibilityByID.set(nodeID, visible)
    return visible
  }

  nodes.forEach((node) => {
    if (!node || typeof node.id !== 'string') return
    isVisible(node.id)
  })

  return new Set(
    [...visibilityByID.entries()]
      .filter((entry) => entry[1] === true)
      .map((entry) => entry[0])
  )
}

function nearestVisibleAncestor(nodeID, visibleNodeIDs, parentsByID) {
  if (visibleNodeIDs.has(nodeID)) {
    return nodeID
  }

  const visited = new Set([nodeID])
  const queue = [nodeID]

  while (queue.length > 0) {
    const currentNodeID = queue.shift()
    const parentIDs = parentsByID.get(currentNodeID) || []

    for (const parentID of parentIDs) {
      if (visited.has(parentID)) {
        continue
      }

      if (visibleNodeIDs.has(parentID)) {
        return parentID
      }

      visited.add(parentID)
      queue.push(parentID)
    }
  }

  return null
}

function model(...nodes) {
  const nodeByID = new Map(nodes.map((node) => [node.id, node]))
  const { parentsByID } = hierarchyMaps(nodes)
  const visibleNodeIDs = visibleNodeIDsByHierarchy(nodes, nodeByID, parentsByID)
  return { nodeByID, parentsByID, visibleNodeIDs }
}

test('multi-parent node remains visible when any parent path is expanded', () => {
  const graph = model(
    { id: 'A', isExpanded: false },
    { id: 'B', isExpanded: true },
    { id: 'X', parentIds: ['A', 'B'] }
  )

  assert.equal(graph.visibleNodeIDs.has('X'), true)
})

test('multi-parent node hides only when all parent paths are collapsed', () => {
  const graph = model(
    { id: 'A', isExpanded: false },
    { id: 'B', isExpanded: false },
    { id: 'X', parentIds: ['A', 'B'] }
  )

  assert.equal(graph.visibleNodeIDs.has('X'), false)
})

test('nearest visible ancestor uses declared parent order deterministically', () => {
  const graph = model(
    { id: 'A', isExpanded: false, parentIds: ['ROOT_1'] },
    { id: 'B', isExpanded: false, parentIds: ['ROOT_2'] },
    { id: 'ROOT_1', isExpanded: true },
    { id: 'ROOT_2', isExpanded: true },
    { id: 'X', parentIds: ['A', 'B'] }
  )

  const nearestAncestor = nearestVisibleAncestor('X', graph.visibleNodeIDs, graph.parentsByID)
  assert.equal(nearestAncestor, 'A')
})

test('nearest visible ancestor returns the first visible direct parent', () => {
  const graph = model(
    { id: 'A', isExpanded: true },
    { id: 'B', isExpanded: true },
    { id: 'X', parentIds: ['A', 'B'] }
  )

  const nearestAncestor = nearestVisibleAncestor('X', graph.visibleNodeIDs, graph.parentsByID)
  assert.equal(nearestAncestor, 'X')
  const ancestorForHiddenChild = nearestVisibleAncestor('CHILD', graph.visibleNodeIDs, new Map([['CHILD', ['A', 'B']]]))
  assert.equal(ancestorForHiddenChild, 'A')
})
