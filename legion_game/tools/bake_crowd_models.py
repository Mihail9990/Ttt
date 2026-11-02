#!/usr/bin/env python3
"""Bake a licensed glTF character animation into six shared-mesh poses.

This creates static pose meshes for efficient GPU MultiMesh crowds. The original
materials and embedded images are retained. No source file is changed.
"""
from __future__ import annotations
import argparse
import copy
import json
import struct
from pathlib import Path
import numpy as np

COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

def read_glb(path: Path):
    data = path.read_bytes()
    magic, version, total = struct.unpack_from('<III', data)
    if magic != 0x46546C67 or version != 2 or total != len(data):
        raise ValueError(f'Invalid glTF 2.0 binary: {path}')
    offset, doc, binary = 12, None, None
    while offset < len(data):
        length, kind = struct.unpack_from('<II', data, offset)
        chunk = data[offset + 8:offset + 8 + length]
        if kind == 0x4E4F534A: doc = json.loads(chunk.decode('utf-8'))
        if kind == 0x004E4942: binary = bytearray(chunk)
        offset += 8 + length
    if doc is None or binary is None: raise ValueError('GLB needs JSON and BIN chunks')
    return doc, binary

def accessor(doc, binary, index):
    a = doc['accessors'][index]
    if 'sparse' in a: raise ValueError('Sparse accessor is not supported')
    v = doc['bufferViews'][a['bufferView']]
    if v.get('buffer', 0) != 0: raise ValueError('External buffers are not supported')
    dtype = np.dtype(COMP[a['componentType']]).newbyteorder('<')
    n = NCOMP[a['type']]
    stride = v.get('byteStride', dtype.itemsize * n)
    offset = v.get('byteOffset', 0) + a.get('byteOffset', 0)
    out = np.ndarray((a['count'], n), dtype=dtype, buffer=binary, offset=offset, strides=(stride, dtype.itemsize)).copy()
    if a.get('normalized') and a['componentType'] != 5126:
        limit = np.iinfo(dtype).max
        out = out.astype(np.float64) / float(limit)
        if np.issubdtype(dtype, np.signedinteger): out = np.maximum(-1.0, out)
    return out

def qmatrix(q):
    q = np.asarray(q, dtype=np.float64)
    q /= max(float(np.linalg.norm(q)), 1e-12)
    x,y,z,w = q
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
                     [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
                     [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]],dtype=np.float64)

def slerp(a, b, t):
    a = np.asarray(a,dtype=np.float64); b = np.asarray(b,dtype=np.float64)
    a /= max(float(np.linalg.norm(a)),1e-12); b /= max(float(np.linalg.norm(b)),1e-12)
    dot = float(np.dot(a,b))
    if dot < 0: b = -b; dot = -dot
    if dot > .9995:
        q = a + t*(b-a)
        return q / max(float(np.linalg.norm(q)),1e-12)
    theta = np.arccos(np.clip(dot,-1,1)); sine = np.sin(theta)
    return (np.sin((1-t)*theta)*a + np.sin(t*theta)*b) / sine

def sample(times, values, t, rotation, interpolation):
    if len(times) == 1 or t <= times[0]: return values[0]
    if t >= times[-1]: return values[-1]
    right = int(np.searchsorted(times, t, side='right')); left = right-1
    fraction = 0.0 if interpolation == 'STEP' else float((t-times[left])/(times[right]-times[left]))
    return slerp(values[left],values[right],fraction) if rotation else values[left]*(1-fraction)+values[right]*fraction

def matrices(doc, binary, anim, t):
    nodes = doc['nodes']
    trs = []
    for n in nodes:
        trs.append({'translation': np.array(n.get('translation',[0,0,0]),dtype=np.float64),
                    'rotation': np.array(n.get('rotation',[0,0,0,1]),dtype=np.float64),
                    'scale': np.array(n.get('scale',[1,1,1]),dtype=np.float64)})
    for channel in anim['channels']:
        target = channel.get('target',{}); kind = target.get('path'); ni = target.get('node')
        if ni is None or kind not in ('translation','rotation','scale'): continue
        s = anim['samplers'][channel['sampler']]; interp = s.get('interpolation','LINEAR')
        if interp not in ('LINEAR','STEP'): raise ValueError('Unsupported animation interpolation '+interp)
        times=accessor(doc,binary,s['input'])[:,0]; values=accessor(doc,binary,s['output'])
        trs[ni][kind] = sample(times,values,t,kind=='rotation',interp)
    local=[]
    for i,n in enumerate(nodes):
        if 'matrix' in n:
            m = np.asarray(n['matrix'],dtype=np.float64).reshape(4,4).T.copy()
        else:
            m = np.eye(4); m[:3,:3] = qmatrix(trs[i]['rotation']) @ np.diag(trs[i]['scale']); m[:3,3] = trs[i]['translation']
        local.append(m)
    parent={child:i for i,n in enumerate(nodes) for child in n.get('children',[])}
    cache={}
    def world(i):
        if i not in cache: cache[i] = (world(parent[i]) @ local[i]) if i in parent else local[i]
        return cache[i]
    return [world(i) for i in range(len(nodes))]

def deformed(doc,binary,node_index,primitive,world):
    node = doc['nodes'][node_index]; attrs=primitive['attributes']
    pos=accessor(doc,binary,attrs['POSITION']).astype(np.float64)
    normals=accessor(doc,binary,attrs['NORMAL']).astype(np.float64) if 'NORMAL' in attrs else None
    hom=np.concatenate((pos,np.ones((len(pos),1))),axis=1)
    if 'skin' not in node:
        result=(world[node_index] @ hom.T).T[:,:3]
        nor=(world[node_index][:3,:3] @ normals.T).T if normals is not None else None
        return result,nor
    skin=doc['skins'][node['skin']]
    ib=accessor(doc,binary,skin['inverseBindMatrices']).reshape(-1,4,4).transpose(0,2,1)
    joints=np.stack([world[j] @ ib[i] for i,j in enumerate(skin['joints'])])
    result=np.zeros((len(pos),3)); nor=np.zeros((len(pos),3)) if normals is not None else None
    for suffix in ['0','1']:
        jk='JOINTS_'+suffix; wk='WEIGHTS_'+suffix
        if jk not in attrs or wk not in attrs: continue
        ji=accessor(doc,binary,attrs[jk]).astype(np.int64)
        weights=accessor(doc,binary,attrs[wk]).astype(np.float64)
        for col in range(ji.shape[1]):
            selected=joints[ji[:,col]]
            result += np.einsum('nij,nj->ni',selected[:,:3,:],hom) * weights[:,col,None]
            if nor is not None:
                nor += np.einsum('nij,nj->ni',selected[:,:3,:3],normals) * weights[:,col,None]
    if nor is not None:
        nor /= np.maximum(np.linalg.norm(nor,axis=1,keepdims=True),1e-12)
    return result,nor

def append_accessor(doc,binary,values):
    values=np.asarray(values,dtype='<f4')
    while len(binary)%4: binary.append(0)
    offset=len(binary); payload=values.tobytes(); binary.extend(payload)
    vi=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':offset,'byteLength':len(payload),'target':34962})
    ai=len(doc['accessors']);doc['accessors'].append({'bufferView':vi,'componentType':5126,'count':len(values),'type':'VEC3','min':values.min(axis=0).astype(float).tolist(),'max':values.max(axis=0).astype(float).tolist()})
    return ai

def bake(src:Path,dst:Path,clip:str,poses:int):
    doc,binary=read_glb(src)
    source_nodes=doc['nodes']; source_meshes=doc['meshes']
    anim=next((a for a in doc.get('animations',[]) if a.get('name','').lower()==clip.lower()),None)
    if anim is None: raise ValueError(f'Animation {clip} not found in {src}')
    duration=max(float(accessor(doc,binary,s['input'])[-1,0]) for s in anim['samplers'])
    model_nodes=[(i,n) for i,n in enumerate(source_nodes) if 'mesh' in n]
    frames=[]
    for frame in range(poses):
        world=matrices(doc,binary,anim,duration*frame/poses)
        pieces=[]
        for ni,node in model_nodes:
            for prim in source_meshes[node['mesh']]['primitives']:
                pos,nor=deformed(doc,binary,ni,prim,world)
                pieces.append((prim,pos,nor))
        frames.append(pieces)
    ys=np.concatenate([p[:,1] for frame in frames for _,p,_ in frame])
    height=float(ys.max()-ys.min())
    if not np.isfinite(height) or height < 1e-5: raise ValueError('Invalid model height')
    scale=1.75/height
    output_meshes=[]; output_nodes=[]
    for i,frame in enumerate(frames):
        allpos=np.concatenate([pos for _,pos,_ in frame],axis=0)
        pivot=np.array([(allpos[:,0].min()+allpos[:,0].max())*.5,allpos[:,1].min(),(allpos[:,2].min()+allpos[:,2].max())*.5])
        outprims=[]
        for original,pos,nor in frame:
            item=copy.deepcopy(original);attrs=item['attributes']
            for key in list(attrs):
                if key.startswith('JOINTS_') or key.startswith('WEIGHTS_'): attrs.pop(key)
            attrs['POSITION']=append_accessor(doc,binary,(pos-pivot)*scale)
            if nor is not None: attrs['NORMAL']=append_accessor(doc,binary,nor)
            item.pop('targets',None)
            outprims.append(item)
        meshid=len(output_meshes);output_meshes.append({'name':f'Pose{i}', 'primitives':outprims})
        output_nodes.append({'name':f'Pose{i}', 'mesh':meshid})
    doc['meshes']=output_meshes;doc['nodes']=output_nodes;doc['scenes']=[{'nodes':list(range(poses))}];doc['scene']=0
    for key in ['skins','animations','cameras']:doc.pop(key,None)
    doc['buffers'][0]['byteLength']=len(binary)
    raw=json.dumps(doc,separators=(',',':'),ensure_ascii=False).encode('utf-8')
    raw += b' '*((-len(raw))%4); binary.extend(b'\0'*((-len(binary))%4))
    dst.parent.mkdir(parents=True,exist_ok=True)
    payload=struct.pack('<III',0x46546C67,2,12+8+len(raw)+8+len(binary))+struct.pack('<II',len(raw),0x4E4F534A)+raw+struct.pack('<II',len(binary),0x004E4942)+binary
    dst.write_bytes(payload)
    print(f'BAKED {src.name}: {poses} frames clip={clip} original_height={height:.3f} bytes={len(payload)}')

def main():
    ap=argparse.ArgumentParser();ap.add_argument('source',type=Path);ap.add_argument('output',type=Path);ap.add_argument('--clip',required=True);ap.add_argument('--poses',type=int,default=6)
    a=ap.parse_args();bake(a.source,a.output,a.clip,a.poses)
if __name__=='__main__': main()
