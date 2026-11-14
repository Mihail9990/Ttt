import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import motionforge as core
import train


class TrainTests(unittest.TestCase):
    def textured_world(self):
        rng=np.random.default_rng(31)
        image=rng.integers(0,256,(240,1500,3),dtype=np.uint8)
        image=cv2.GaussianBlur(image,(3,3),0)
        for i in range(40):
            cv2.circle(image,(int(rng.integers(10,1490)),int(rng.integers(10,230))),
                       int(rng.integers(3,14)),tuple(map(int,rng.integers(0,256,3))),-1)
        return image

    def test_registration_recovers_shared_geography(self):
        world=self.textured_world()
        matrix,report=train.register_neighbor(world[:,:800],world[:,500:1300])
        self.assertGreater(report['inliers'],100)
        self.assertAlmostEqual(matrix[0,2],500,delta=1)
        self.assertAlmostEqual(matrix[1,2],0,delta=1)
        self.assertLess(report['median_alignment_error_pixels'],1)

    def test_unrelated_landscape_is_rejected_instead_of_faded(self):
        a=np.full((240,800,3),80,np.uint8)
        b=np.full((240,800,3),180,np.uint8)
        with self.assertRaisesRegex(core.EngineError,'shared landscape'):
            train.register_neighbor(a,b)

    def test_spatial_join_reconstructs_known_world(self):
        world=self.textured_world()
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            Image.fromarray(world[:,:800]).save(root/'a.png')
            Image.fromarray(world[:,500:1300]).save(root/'b.png')
            panorama,report=train.build_panorama([root/'a.png',root/'b.png'],height=240)
            self.assertAlmostEqual(panorama.shape[1],1300,delta=2)
            self.assertEqual(report['time_crossfades'],0)
            error=np.abs(panorama[15:-15,100:1200].astype(float)-world[15:-15,100:1200]).mean()
            self.assertLess(error,2)

    def test_camera_is_monotone_with_continuous_speed(self):
        path=train.CameraPath([{'time':0,'u':0},{'time':60,'u':.64},{'time':84,'u':1}],84)
        values=[path.at(t) for t in np.linspace(0,84,1000)]
        self.assertTrue((np.diff(values)>=0).all())
        self.assertAlmostEqual(path.at(0),0)
        self.assertAlmostEqual(path.at(84),1)
        eps=.001
        before=(path.at(60)-path.at(60-eps))/eps
        after=(path.at(60+eps)-path.at(60))/eps
        self.assertAlmostEqual(before,after,delta=.00001)

    def test_window_frames_are_not_time_dissolves(self):
        # A known horizontal intensity ramp must be sampled at the camera position.
        columns=np.arange(600,dtype=np.float32)/600*220
        world=np.repeat(np.repeat(columns[None,:,None],180,axis=0),3,axis=2).astype(np.uint8)
        scene=train.WindowView(world,320,180,[{'time':0,'u':0},{'time':1,'u':1}],1,
                               foreground=False,window=False)
        first=scene.render(0);middle=scene.render(.5);last=scene.render(1)
        self.assertLess(abs(float(first[90,160,0])-float(world[90,162,0])),1)
        expected_x=round(2+scene.distance*.5+160)
        self.assertLess(abs(float(middle[90,160,0])-float(world[90,expected_x,0])),1)
        self.assertGreater(float(last[90,160,0])-float(first[90,160,0]),90)

    def test_window_border_stays_fixed(self):
        world=np.full((180,600,3),150,np.uint8)
        scene=train.WindowView(world,320,180,[{'time':0,'u':0},{'time':1,'u':1}],1)
        a,b=scene.render(0),scene.render(.8)
        self.assertTrue(np.array_equal(a[0,0],b[0,0]))
        self.assertLess(float(a[0,0].mean()),50)
        self.assertGreater(float(a[90,160].mean()),100)

    def test_short_train_export_has_exact_duration(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            Image.fromarray(self.textured_world()).save(root/'pano.png')
            project={'width':320,'height':180,'fps':12,'seconds':.5,
                     'panorama':'pano.png','foreground':True,'window':True,
                     'camera_keys':[{'time':0,'u':0},{'time':.5,'u':1}]}
            (root/'project.json').write_text(json.dumps(project))
            with contextlib.redirect_stdout(io.StringIO()):
                report=train.render(root/'project.json',root/'train.mp4',threads=2)
            self.assertEqual(report['frames'],6)
            self.assertEqual(report['duration_seconds'],.5)
            self.assertEqual(report['time_crossfades'],0)
            cap=cv2.VideoCapture(str(root/'train.mp4'))
            self.assertEqual(int(cap.get(cv2.CAP_PROP_FRAME_COUNT)),6)
            self.assertTrue(cap.read()[0]);cap.release()

    def test_generated_continuations_have_real_shared_features(self):
        folder=train.ROOT/'assets/train'
        images=[core.load_rgb(folder/name) for name in ['01_mountains.jpg','02_mountains.jpg','03_forest.jpg']]
        for a,b in zip(images,images[1:]):
            matrix,report=train.register_neighbor(a,b)
            self.assertGreater(report['inliers'],100)
            self.assertLess(report['median_alignment_error_pixels'],2)


if __name__=='__main__':
    unittest.main()
