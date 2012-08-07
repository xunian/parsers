package parser
{
	import away3d.animators.SkeletonAnimationSet;
	import away3d.animators.data.Skeleton;
	import away3d.animators.data.SkeletonJoint;
	import away3d.arcane;
	import away3d.core.base.Geometry;
	import away3d.core.base.SkinnedSubGeometry;
	import away3d.core.base.data.UV;
	import away3d.core.math.Quaternion;
	import away3d.entities.Mesh;
	import away3d.events.AssetEvent;
	import away3d.library.assets.IAsset;
	import away3d.loaders.Loader3D;
	import away3d.loaders.misc.ResourceDependency;
	import away3d.loaders.parsers.ParserBase;
	import away3d.loaders.parsers.ParserDataFormat;
	import away3d.loaders.parsers.utils.ParserUtil;
	import away3d.materials.ColorMaterial;
	import away3d.materials.TextureMaterial;
	import away3d.textures.BitmapTexture;
	
	import flash.geom.Matrix3D;
	import flash.geom.Vector3D;
	import flash.net.URLRequest;
	import flash.utils.getTimer;
	
	use namespace arcane;
	
	public class ParserMeshFormat extends ParserBase
	{
		
		private var m_xml:XML;
		private var _faceData:FaceData;
		private var assRoot:Array;
		private var m_mesh:Mesh;
		private var m_loader:Loader3D;
		private var m_mtls:Array;
		private var textures:Array;
		private var m_parmStr:*;
		
		private var _str:String ;
		private var m_filename:String;
		
		private var m_textureBoolean:Boolean = false;
		private var m_skeletonBoolean:Boolean = false ;
		private var _start:Boolean = true ;
		private var loadMaterial:Boolean = false ;
		
		private var m_skeletonXML:*;
		private var m_joints:Array;
		
		private var _vertexbuffer:Vertexbuffer;
		private var _weightData:Vector.<Number> ;
		private var _bindPoses:Vector.<Matrix3D>;
		private var _animationSet:SkeletonAnimationSet;
		private var _skeleton:Skeleton;
		private var _jointindices:Vector.<Number>;
		private var _meshData:MeshData;
		private var _maxJointCount:int;
		private var _countWeightData:Array;
		private var _vertexcount:int;
		
		public function ParserMeshFormat(format:String="")
		{
			super(ParserDataFormat.PLAIN_TEXT);
		}
		
		override protected function proceedParsing() : Boolean
		{
			if(_start)
			{	
				_start = false ;
				m_xml = new XML( _data );
				parserLine(); 
			}
		
			if ( parsingPaused )
				return MORE_TO_PARSE;
			
			if( m_textureBoolean && m_skeletonBoolean )
			{
				calculateMaxJointCount();
				_animationSet = new SkeletonAnimationSet(_maxJointCount);
				
				var geometry:Geometry ;
				geometry = m_mesh.geometry ;
				geometry.addSubGeometry( getSkinnedSubGeometry(_animationSet.jointsPerVertex, _vertexbuffer.vertexDatas , _faceData.vertexIndices , _vertexbuffer.uv , _weightData , _jointindices ,  _vertexbuffer.normalDatas) );
				
				finalizeAsset(  m_mesh , "AAA" );
				finalizeAsset(  _skeleton , "_skeleton" );
				finalizeAsset(  _animationSet , "AAA" );
				return PARSING_DONE;
			}
			else 
				parserMaterial();
			
			return MORE_TO_PARSE ;
		}
		
		private function calculateMaxJointCount() : void
		{
			_maxJointCount = 0;
			var count:int; 
			
			for (var j : int = 0; j < _vertexcount; ++j) {
				count = _countWeightData[j].length ;
				if( _maxJointCount < count )
					_maxJointCount = count ;
			}
		}
		
		private function getSkinnedSubGeometry( num:Number , vertexData : Vector.<Number> , indices : Vector.<uint> , uvs : Vector.<Number> , jointWeights : Vector.<Number> , jointindices : Vector.<Number> , normalData:Vector.<Number> ):SkinnedSubGeometry
		{
			var skinnedSubGeometry:SkinnedSubGeometry = new SkinnedSubGeometry(num);
			
			skinnedSubGeometry.updateVertexData( vertexData );
			skinnedSubGeometry.updateVertexNormalData( normalData );
			skinnedSubGeometry.updateIndexData( indices );
			skinnedSubGeometry.updateUVData( uvs );
			skinnedSubGeometry.updateJointIndexData(jointindices);
			skinnedSubGeometry.updateJointWeightsData(jointWeights);
			
			return skinnedSubGeometry ;
		}
		
		private function parserLine():void
		{
			m_mesh = new Mesh( new Geometry());
			_meshData = new MeshData();
			parsegeometry();
				
			parseFace();
			
			parserMaterial();
			
			parserSkeletons();
			
		}
		
		/**
		 *<vertexboneassignment vertexindex="0" boneindex="23" weight="0.5" /> 
		 */
		private function parserSkeletons():void
		{
			var i:int;
			var jointData:JointData;
			var skeleton:Skeletons = new Skeletons(); 
			var vertexboneassignment:Vertexboneassignment;
			_meshData.weightData = new Vector.<JointData>();
			
			skeleton.name = m_xml.skeletonlink.@name ;
			
			_weightData = new Vector.<Number>();
			_jointindices = new Vector.<Number>();
			_countWeightData = [];
			
			for ( i = 0 ; i < m_xml.boneassignments.vertexboneassignment.length() ; i++ ) 
			{

				vertexboneassignment = new Vertexboneassignment();
				
				var weight:Number = m_xml.boneassignments.vertexboneassignment[i].@weight ;
				_weightData.push( weight );
				
				var weightIndice:int = m_xml.boneassignments.vertexboneassignment[i].@vertexindex ;
				_jointindices.push( weightIndice );
				
				var boneindexIndice:int = m_xml.boneassignments.vertexboneassignment[i].@boneindex ;
				
				vertexboneassignment.vertexindex = weightIndice ;
				vertexboneassignment.weight = weight ;
				vertexboneassignment.boneindex = boneindexIndice ;
				
				_countWeightData[weightIndice] ||= [] ;
				
				_countWeightData[weightIndice].push( vertexboneassignment );
				
			}
			
			addDependency( "SKELETON" , new URLRequest( skeleton.name + ".xml" ), true );
			
		}
		
		private function parserMaterial():void
		{
			
			var loadedMaterial:LoadedMaterial = new LoadedMaterial();
			loadedMaterial.materialID = m_xml.submeshes.submesh.@material ;
			loadedMaterial.usesharedvertices = m_xml.submeshes.submesh.@usesharedvertices ; 
			loadedMaterial.use32bitindexes = m_xml.submeshes.submesh.@use32bitindexes ; 
			loadedMaterial.operationtype = m_xml.submeshes.submesh.@operationtype ;
			
			assRoot =  _fileName.split("/") ;
			assRoot.pop() ;
			assRoot[0] += "/" ;
			
			addDependency('material', new URLRequest(loadedMaterial.materialID+".material"), true);
			pauseAndRetrieveDependencies();
		}
		
		override arcane function resolveDependency(resourceDependency : ResourceDependency) : void
		{
			var i:int ;
			
			if( resourceDependency.id == "material" )
			{	m_mtls = [] ;
				var str : String = ParserUtil.toString(resourceDependency.data);
				textures = String(str).split( "texture_unit" );
				m_parmStr = textures.shift() ;
				for ( i = 0 ; i < 1 ; i++)  //textures.length
				{
					var libs:Array = String(textures[i]).split( "texture" ) ;
					var fileName:String = getPar( libs[1] );
					var url:String = assRoot + fileName ;
					addDependency( "texture" , new URLRequest( fileName ) );
				}
			
			}
			else if( resourceDependency.id == "texture" )
			{
				var asset:IAsset;
				
				if (resourceDependency.assets.length != 1)
					return;
				
				asset = resourceDependency.assets[0];
				
				m_mesh.material = new TextureMaterial( asset as BitmapTexture );
				
//				resumeParsingAfterDependencies();
				m_textureBoolean = true ;
				
			}
			else if( resourceDependency.id == "SKELETON" )
			{ 
				var joint:SkeletonJoint 
				var pos : Vector3D;
				var quat : Quaternion;
				m_joints = [] ;
				
				m_skeletonXML = new XML(ParserUtil.toString(resourceDependency.data));
				var skeletonNum:int = m_skeletonXML.bones.bone.length();
				
				_bindPoses = new Vector.<Matrix3D>(skeletonNum, true);
				
				_skeleton = new Skeleton();
				
				for (i = 0 ; i < skeletonNum ; i++) 
				{
					var skeletonJoint:SkeletonJoint = new SkeletonJoint();
					joint = new SkeletonJoint();
					joint.name = m_skeletonXML.bones.bone[i].@name ;
//					joint.parentIndex = tmp;
					m_joints[ joint.name ] = int(m_skeletonXML.bones.bone[i].@id) ;
					
					pos = new Vector3D();
					pos.x = m_skeletonXML.bones.bone[i].position.@x;
					pos.y = m_skeletonXML.bones.bone[i].position.@y;
					pos.z = m_skeletonXML.bones.bone[i].position.@z;
					
					
//					pos = _rotationQuat.rotatePoint(pos);
					quat = parseQuaternion( m_skeletonXML.bones.bone[i].rotation.axis.@x , m_skeletonXML.bones.bone[i].rotation.axis.@y
										  , m_skeletonXML.bones.bone[i].rotation.axis.@z , m_skeletonXML.bones.bone[i].rotation.@angle );
					
					// todo: check if this is correct, or maybe we want to actually store it as quats?
					_bindPoses[i] = quat.toMatrix3D();
					_bindPoses[i].appendTranslation(pos.x, pos.y, pos.z);
					
					var inv : Matrix3D = _bindPoses[i].clone();
					inv.invert();
					joint.inverseBindPose = inv.rawData;
					
					
					_skeleton.joints[i] = joint;
				}
				
				for ( i = 0 ; i < skeletonNum ; i++) 
				{
					var jointName:String = _skeleton.joints[i].name ; 
					var parentJointName:String = m_skeletonXML.bonehierarchy.boneparent.(@bone == jointName).@parent ;
					_skeleton.joints[i].parentIndex = m_joints[ parentJointName ] ;
				}
				
				m_skeletonBoolean = true ;
			}
			
		}
		
		
		
		/**
		 * Retrieves the next quaternion in the data stream.
		 */
		private function parseQuaternion( rx:Number , ry:Number  ,rz:Number , angle :Number ) : Quaternion
		{
			var quat : Quaternion = new Quaternion();
			
//			quat.x = rx;
//			quat.y = ry;
//			quat.z = rz;
			
			quat.fromAxisAngle( new Vector3D( rx , ry , rz ) , angle );
			
			// quat supposed to be unit length
			var t : Number = 1 - quat.x * quat.x - quat.y * quat.y - quat.z * quat.z;
			quat.w = t < 0 ? 0 : -Math.sqrt(t);
			
//			var rotQuat : Quaternion = new Quaternion();
//			rotQuat.multiply(_rotationQuat, quat);
			
			return quat;
		}
		
		/**
		 * @inheritDoc
		 */
		public function __onMaterialComplete(e:AssetEvent):void
		{
			m_mesh.material = e.asset as TextureMaterial ;
		
		}
		
		/** 
		 *    <submeshes>
       		 <submesh material="01_-_Default" usesharedvertices="true" use32bitindexes="false" operationtype="triangle_list">
          	  <faces count="24">
			  *  <face v1="0" v2="1" v3="2" />
		 */
		private function parseFace():void
		{
			// TODO Auto Generated method stub
			var i:int = 0 ;
			
			_faceData = new FaceData();
			_faceData.faceCount = m_xml.submeshes.submesh.faces.@count ;
			
			for ( i = 0 ; i < _faceData.faceCount; i++) 
			{
				_faceData.vertexIndices.push( m_xml.submeshes.submesh.faces.face[i].@v1 );
				_faceData.vertexIndices.push( m_xml.submeshes.submesh.faces.face[i].@v2 );
				_faceData.vertexIndices.push( m_xml.submeshes.submesh.faces.face[i].@v3 );
				
				_faceData.normalIndices.push( m_xml.submeshes.submesh.faces.face[i].@v1 );
				_faceData.normalIndices.push( m_xml.submeshes.submesh.faces.face[i].@v2 );
				_faceData.normalIndices.push( m_xml.submeshes.submesh.faces.face[i].@v3 );
			}
		}
		
		/**
		 *  <sharedgeometry vertexcount="72">
		 <vertexbuffer positions="true" normals="true" texture_coord_dimensions_0="2" texture_coords="1">
		 <vertex>
		 <position x="0.39415" y="1.5" z="0.159247" />
		 <normal x="0" y="1" z="-0" />
		 <texcoord u="0.75" v="0" />
		 </vertex>
		 </vertexbuffer>
		 </sharedgeometry> 
		 * 
		 */
		private function parsegeometry():void
		{
			var i:int ;
			var pos:Vector3D = new Vector3D();
			var normalPos:Vector3D = new Vector3D();
			var uv:UV = new UV();
			
			_vertexcount = m_xml.sharedgeometry.@vertexcount;
			
			_vertexbuffer = new Vertexbuffer();
			_vertexbuffer.positions 		  = m_xml.sharedgeometry.vertexbuffer.@positions ;
			_vertexbuffer.normals		  = m_xml.sharedgeometry.vertexbuffer.@normals ;
			_vertexbuffer.texture_coord_dimensions_0 =  m_xml.sharedgeometry.vertexbuffer.@texture_coord_dimensions_0 ;
			_vertexbuffer.texture_coords = m_xml.sharedgeometry.vertexbuffer.@texture_coords ;
			
			var t:Number = getTimer() ;
			for ( i = 0 ; i < _vertexcount ; i++) 
			{
				pos.x = m_xml.sharedgeometry.vertexbuffer[0].vertex[i].position.@x ;
				pos.y = m_xml.sharedgeometry.vertexbuffer[0].vertex[i].position.@y ;
				pos.z = m_xml.sharedgeometry.vertexbuffer[0].vertex[i].position.@z ;
				_vertexbuffer.vertexDatas.push( pos.x );
				_vertexbuffer.vertexDatas.push( pos.y );
				_vertexbuffer.vertexDatas.push( pos.z );
				
				normalPos.x = m_xml.sharedgeometry.vertexbuffer[0].vertex[i].normal.@x ;
				normalPos.y = m_xml.sharedgeometry.vertexbuffer[0].vertex[i].normal.@y ;
				normalPos.z = m_xml.sharedgeometry.vertexbuffer[0].vertex[i].normal.@z ;
				_vertexbuffer.normalDatas.push( normalPos.x );
				_vertexbuffer.normalDatas.push( normalPos.y );
				_vertexbuffer.normalDatas.push( normalPos.z );
				
				uv.u = m_xml.sharedgeometry.vertexbuffer[1].vertex[i].texcoord.@u ;
				uv.v = m_xml.sharedgeometry.vertexbuffer[1].vertex[i].texcoord.@v ;
				_vertexbuffer.uv.push( uv.u );
				_vertexbuffer.uv.push( uv.v );
			}
			trace( getTimer() - t ); 
		}
		
		private function getPar( str:* ):String
		{
			_str = str;
			var stt:String = "";
			var nexStr:String ;
			
			var count:int = 0 ;
			do 
			{
				nexStr = readNext(count) ;
				count++;
				if( nexStr != " " && nexStr != "%")
					stt += nexStr ;
				
			} while(_str.length>count && nexStr != "%" )
			
			return stt ;
		}
		
		/**
		 * 读取下一个字符 
		 * @param str
		 * @return 
		 * 
		 */
		private function readNext( index:int ):String
		{
			_str = _str.replace( "\r" , "%" );
			_str = _str.replace( "\t" , " " );
			_str = _str.replace( "\n" , " " );
			_str = _str.replace( "}" , " " );
			_str = _str.replace( "{" , " " );
			return _str.charAt(index);
		}
		
		
	}
}





import away3d.materials.methods.BasicSpecularMethod;
import away3d.textures.Texture2DBase;

import flash.geom.Vector3D;

class Sharedgeometry
{
	public var vertexcount:int;
	public var vertexbuffer:Vertexbuffer;
}

class Vertexbuffer
{
	public var positions:Boolean ;
	public var normals:Boolean ;
	public var texture_coord_dimensions_0:int;
	public var texture_coords:int;
	
	public var vertexDatas:Vector.<Number> = new Vector.<Number>();
	public var normalDatas:Vector.<Number> = new Vector.<Number>();
	public var uv:Vector.<Number> = new Vector.<Number>();
}

class SpecularData
{
	public var materialID:String;
	public var basicSpecularMethod:BasicSpecularMethod;
	public var ambientColor:uint = 0xFFFFFF;
	public var alpha:Number = 1;
}

class LoadedMaterial
{
	import away3d.materials.ColorMaterial;
	
	public var materialID:String;
	public var texture:Texture2DBase;
	public var cm:ColorMaterial;
	public var specularMethod:BasicSpecularMethod;
	public var ambientColor:uint = 0xFFFFFF;
	public var alpha:Number = 1;
	
	public var usesharedvertices:Boolean  ;
	public var use32bitindexes:Boolean  ;
	public var operationtype:String  ;
}


class FaceData
{
	public var faceCount:int;
	public var vertexIndices:Vector.<uint> = new Vector.<uint>();
	public var uvIndices:Vector.<uint> = new Vector.<uint>();
	public var normalIndices:Vector.<uint> = new Vector.<uint>();
	public var indexIds:Vector.<String> = new Vector.<String>();	// used for real index lookups
}

class Skeletons
{
	public var name:String;
}

class Vertexboneassignment
{
	public var vertexindex:int ;
	public var weight:int;
	public var boneindex:int;
}




class VertexData
{
	public var index : int;
	public var s : Number;
	public var t : Number;
	public var startWeight : int;
	public var countWeight : int;
}

class JointData
{
	public var index : int;
	public var joint : int;
	public var bias : Number;
	public var pos : Vector3D;
}

class MeshData
{
	public var vertexData : Vector.<VertexData>;
	public var weightData : Vector.<JointData>;
	public var indices : Vector.<uint>;
}
