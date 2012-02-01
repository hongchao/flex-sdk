////////////////////////////////////////////////////////////////////////////////
//
//  ADOBE SYSTEMS INCORPORATED
//  Copyright 2003-2008 Adobe Systems Incorporated
//  All Rights Reserved.
//
//  NOTICE: Adobe permits you to use, modify, and distribute this file
//  in accordance with the terms of the license agreement accompanying it.
//
////////////////////////////////////////////////////////////////////////////////

package mx.filters {  

import flash.display.Shader;
import flash.display.ShaderInput;
import flash.display.ShaderParameter;
import flash.display.ShaderParameterType;
import flash.display.ShaderPrecision;
import flash.events.Event;
import flash.events.EventDispatcher;
import flash.events.IEventDispatcher;
import flash.filters.BitmapFilter;
import flash.filters.ShaderFilter;
import flash.utils.ByteArray;
import flash.utils.Proxy;
import flash.utils.flash_proxy;

import mx.filters.BaseFilter;
import mx.filters.IBitmapFilter;

use namespace flash_proxy;

/**
 * The Flex ShaderFilter class abstracts away many of the details of using
 * the stock Flash ShaderFilter, Shader, and ShaderData classes to apply a
 * Pixel Bender shader as a filter.
 *
 * <p>The ShaderFilter class must be initialized with byte code representing a
 * compiled Pixel Bender shader. After that the class will create (behind the scenes) a
 * Shader instance from the byte code. The ShaderFilter class then serves as a proxy to the
 * underlying Shader, providing a convenience mechanism for accessing both scalar
 * and multi-dimensional shader input parameters directly as simple named properties.</p>
 *
 * <p>To set a simple scalar shader input parameter (e.g. of type FLOAT or INT), you can simply
 * refer to the property directly, e.g. <code>myFilter.radius</code>.</p>
 *
 * <p>To set or animate an individual component of a  multidimensional shader input parameter (such as 
 * FLOAT2) you can use a property suffix convention to address the individual value directly. For 
 * instance the following are equivalent means of settting the first and second components of the FLOAT2
 * property 'center':
 * <code><pre>
 *     // 'center' is an input parameter of type FLOAT2.
 *     shader.center = [10,20];
 * </pre></code>
 * <code><pre>
 *     // Alternate means of addressing the first and second component of 'center'. 
 *     shader.center_x = 10;
 *     shader.center_y = 20;
 * </pre></code></p>
 *
 * <p>The full set of supported convenience suffixes are as follows: </p>
 *
 * <p>For shader input parameters of type BOOL2, BOOL3, BOOL4, FLOAT2, FLOAT3, FLOAT4, INT2, 
 * INT3, or INT4, either "r g b a", "x y z w", or "s t p q" may be utilized as convenience suffixes 
 * to access the 1st, 2nd, 3rd and 4th component respectively.</p>
 *
 * <p>For shader input parameters of type MATRIX2x2, MATRIX3x3, or MATRIX4x4, 
 * 'a b c d e f g h i j k l m n o p" may be used as property suffixes to access the 
 * 1st - 16th component of a given matrix.</p>
 *
 * <p>Note that as properties on the ShaderFilter change (such as during animation), the
 * ShaderFilter will automatically re-apply itself to the filters array of the visual
 * component it is applied to.</p>
 *
 * @see mx.effects.FxAnimateFilter 
 *
 * @example Simple ShaderFilter example:
 * <listing version="3.0">
 * &lt;?xml version="1.0"?&gt;
 * &lt;FxApplication xmlns="http://ns.adobe.com/mxml/2009"&gt;
 *
 *     &lt;!-- The hypothetical 'spherize' shader applied below has two input parameters, 'center' and 'radius'
 *          with the following attributes:
 *
 *          parameter 'center' ==&lt;
 *              type: float2
 *              minValue: float2(-200,-200)
 *              maxValue: float2(800,500)
 *              defaultValue: float2(400,250)
 *              description: "displacement center"
 *  
 *          parameter 'radius' ==&lt;
 *              type: float
 *              minValue: float(.1)
 *              maxValue: float(400)
 *              defaultValue: float(200)
 *              description: "radius"
 *     --&gt;
 *  
 *     &lt;Label text="ABCDEF"&gt;
 *         &lt;filters&gt;
 *             &lt;ShaderFilter byteCode="&#64;Embed(source="shaders/spherize.pbj', mimeType='application/octet-stream')"
 *                 radius="25" center_x="50" center_y="15" /&gt;
 *        &lt;/filters&gt;
 *     &lt;/Label&gt;
 *   
 * &lt;/FxApplication&gt; 
 * </listing>
 */
public dynamic class ShaderFilter extends Proxy
    implements IBitmapFilter, IEventDispatcher
{  
    //--------------------------------------------------------------------------
    //
    //  Variables
    //
    //--------------------------------------------------------------------------
         
    /**
     * Private storage for incoming properties, queued until
     * shader is initialized and available.
     */
    private var propertyQueue:Object;  
          
    //--------------------------------------------------------------------------
    //
    //  Constructor
    //
    //--------------------------------------------------------------------------

    /**
     *  Constructor.
     *  @param byteCode Compiled Pixel Bender byte code as ByteArray or Class.
     */ 
    public function ShaderFilter(byteCode:*=null)  
    {  
        super();
        eventDispatcher = new EventDispatcher();
        this.byteCode = byteCode;         
    }  
     
    //--------------------------------------------------------------------------
    //
    //  Properties
    //
    //--------------------------------------------------------------------------
    
    //----------------------------------
    //  shaderInstance
    //----------------------------------
    /**
     *  @private
     *  Storage for the shaderInstance property.
     */
    private var _shader:Shader;
    
    /**
     * flash.display.Shader instance (valid once byteCode is assigned).
     */  
    public function get shaderInstance():Shader
    {
        return _shader;
    }
 
    //----------------------------------
    //  byteCode
    //----------------------------------
    
    /**
     *  @private
     *  Storage for the custom filter byteCode.
     */
    private var _byteCode:*;
 
    /**
     * The shader bytecode for this Shader instance, either a Class or ByteArray
     * instance.
     */
    public function set byteCode(value:*):void
    {
        // Since our bytecode is sometimes reassigned by the
        // binding infrastructure we only initialize ourselves
        // upon the first instance.
        if (value == _byteCode)
            return;
            
        // Create our shader instance from the byteCode provided.
        if (value is ByteArray)
        {
            _shader = new Shader(value);
        }
        else if (value is Class)
        {
            var obj:* = new value();
            if (obj is Shader)
                _shader = obj as Shader; 
            else if (obj is ByteArray)
                _shader = new Shader(obj as ByteArray);
        }

        // Push any pending properties onto the new shader instance. 
        applyQueuedProperties();
            
        // Our new filter is ready to do its work.
        notifyFilterChanged();
        _byteCode = value;
    }

    //----------------------------------
    //  bottomExtension
    //----------------------------------

    private var _bottomExtension:Number = 0.0;

    /**
     *  @copy flash.filters.ShaderFilter#bottomExtension
     */
    public function get bottomExtension():Number
    {
        return _bottomExtension;
    }

    public function set bottomExtension(value:Number):void
    {
        if (value == _bottomExtension)
            return;
        
        _bottomExtension = value;
        notifyFilterChanged();
    }

    //----------------------------------
    //  topExtension
    //----------------------------------

    private var _topExtension:Number = 0.0;

    /**
     *  @copy flash.filters.ShaderFilter#topExtension
     */
    public function get topExtension():Number
    {
        return _topExtension;
    }

    public function set topExtension(value:Number):void
    {
        if (value == _topExtension)
            return
        
        _topExtension = value;
        notifyFilterChanged();
    }

    //----------------------------------
    //  leftExtension
    //----------------------------------

    private var _leftExtension:Number = 0.0;

    /**
     *  @copy flash.filters.ShaderFilter#leftExtension
     */
    public function get leftExtension():Number
    {
        return _leftExtension;
    }

    public function set leftExtension(value:Number):void
    {
        if (value == _leftExtension)
            return;
        
        _leftExtension = value;
        notifyFilterChanged();
    }

    //----------------------------------
    //  rightExtension
    //----------------------------------

    private var _rightExtension:Number = 0.0;

    /**
     *  @copy flash.filters.ShaderFilter#rightExtension
     */
    public function get rightExtension():Number
    {
        return _rightExtension;
    }

    public function set rightExtension(value:Number):void
    {
        if (value == _rightExtension)
            return;
        
        _rightExtension = value;
        notifyFilterChanged();
    }
    
    //----------------------------------
    //  precisionHint
    //----------------------------------

    /**
     * @private
     */  
    private var _precisionHint:String = ShaderPrecision.FULL;

    /**
     * The precision of math operations performed by the underlying shader.
     * The set of possible values for the precisionHint property is defined 
     * by the constants in the ShaderPrecision class.
     * 
     *  @see flash.display.Shader
     */
    public function get precisionHint():String
    {
        return _precisionHint;
    }

    public function set precisionHint(value:String):void
    {
        if (value == _precisionHint)
            return;
        
        _precisionHint = value;
        notifyFilterChanged();
    }

    //--------------------------------------------------------------------------
    //
    //  ShaderData Proxy
    //
    //--------------------------------------------------------------------------

    /**
     * @private
     * Proxies all property 'gets' to the owned shader instance or
     * our propertyQueue otherwise.
     */     
    override flash_proxy function getProperty(name:*):*
    {
        return (_shader) ? retrieveShaderProperty(name) : propertyQueue[name];
    }

    /**
     * @private
     * Proxies all property 'sets' to the owned shader instance.
     * If the shader bytecode has yet to be set or instanced, we
     * queue the properties for later application.
     */ 
    override flash_proxy function setProperty(name:*, value:*):void 
    {            
        if (_shader)
        {
            // We have a shader, push all properties to the shader
            // instance itself.
            applyProperty(name.toString(), value);
            notifyFilterChanged();
        }
        else
        {
            // The shader has yet to be initialized, queue any properties,
            // the will be applied upon creation of the shader.
            propertyQueue = propertyQueue ? propertyQueue : new Object();
            propertyQueue[name] = value;
        }
    }
    
    /**
     * @private
     * Proxies method calls to our shader instance.
     */ 
    override flash_proxy function callProperty(name:*, ... args):*
    {
        if (_shader) 
            return _shader[name].apply(_shader, args);
    }

    /**
     * @private
     * Required to support property 'in' operator.
     */ 
    override flash_proxy function hasProperty(name:*):Boolean
    {
        if (!_shader || !name || name == "")
            return false;
            
        var index:int = name.indexOf("_");
        var prefix:String = (index > 0) ? name.substring(0, index) : name;
            
        return (name in _shader || name in _shader.data || prefix in _shader.data);
    }
    
    /**
     * @private
     * Apply our queued properties once our shader instance has
     * been constructed and initialized from its bytecode.
     */
    private function applyQueuedProperties():void
    {
        if (_shader)
        {
            for (var property:String in propertyQueue)
            {   
                applyProperty(property, propertyQueue[property]); 
            }
            
            propertyQueue = null;
        }
    }  
 
    /**
     * @private
     * Apply a single property value, provides special case conventions for 
     * targetting specific indexes of multi-dimensional shader properties.
     * 
     * If the property identifier fits the pattern 'NAME_<S>' and the value
     * being set is a scalar, we look for a matching multidimension shader 
     * input parameter 'NAME' and interpret the provide suffix 'S' as a named 
     * dimension as detailed below (indexForDimension). 
     *
     * We interpret the property name 'as is' otherwise (if 'NAME' does not 
     * match an n-dimensional property, or if the value provided is a scaler).
     */
    private function applyProperty(property:String, value:*):void
    {
        if (value == null) 
            return;
        
        var suffixPattern:RegExp = /_.$/;
        var match:Array = property.match(suffixPattern);
        
        // If this property name contains a suffix, attempt to push the value
        // to the specified component of a multi-dimensional property.
        if (match && match[0] && !(value is Array))
        {
            var suffix:String = match[0];
            var name:String = property.substr(0, property.length - suffix.length);
            var dimension:String = suffix.substr(suffix.length-1, 1);
            
            var propertyInfo:ShaderParameter = _shader.data[name];
            if (propertyInfo)
            {
                var index:int = indexForDimension(propertyInfo.type, dimension);
                if (index != -1)
                {
                    var currentValue:Array = propertyInfo.value ? propertyInfo.value : new Array();
                    currentValue[index] = value;
                    propertyInfo.value = currentValue;
                    return;
                }
            }
        }
        
        // Otherwise if the target property is a ShaderInput instance or
        // array property, set the value.
        if (_shader.data[property] is ShaderInput)
            _shader.data[property].input = value;
        else
            _shader.data[property].value = (value is Array) ? value : [value];
    }  
    
    /**
     * @private
     * Retrieve a single property value, provides special case conventions for 
     * retrieving specific components of multi-dimensional shader properties.
     */
    private function retrieveShaderProperty(name:*):*
    {
        name = (name is QName) ? name.localName : name;
        var suffixPattern:RegExp = /_.$/;
        var match:Array = name.match(suffixPattern);
        
        // If this property name contains a suffix, attempt to retrieve the value
        // from the specified component of a multi-dimensional property.
        if (match && match[0])
        {
            var suffix:String = match[0];
            var prop:String = name.substr(0, name.length - suffix.length);
            var dimension:String = suffix.substr(suffix.length-1, 1);
            
            var propertyInfo:ShaderParameter = _shader.data[prop];
            if (propertyInfo)
            {
                var index:int = indexForDimension(propertyInfo.type, dimension);
                if (index != -1)
                    return propertyInfo.value[index];
            }
        }
        
        // Otherwise return the appropriate value for the property type.
        return (_shader.data[name] is ShaderInput) ? 
            _shader.data[name].input : 
            _shader.data[name].value;  
    }
    
    /**
     * @private
     * Given a property of the form property_<S> where S is a single
     * character representing a named dimension of a multi-dimensional
     * parameter, return the associated numeric index.
     */
    private function indexForDimension(type:String, dimension:String):int
    {
       var index:int = 0;
       
       if (type == ShaderParameterType.MATRIX2X2 ||
           type == ShaderParameterType.MATRIX3X3 ||
           type == ShaderParameterType.MATRIX4X4)
       {
           // "abcdefghijklmnop" convenience access to:
           //   MATRIX 2x2, MATRIX3x3, or MATRIX4x4
           index = dimension.charCodeAt(0) - 0x61; // 'a' 
       }
       else if (Number(type.charAt(type.length - 1)) > 0)
       {
           // "rgba", "xyzw", or "stpq" convenience access to:
           //  BOOL2, BOOL3, BOOL4, FLOAT2, FLOAT3, FLOAT4, 
           //  INT2, INT3, or INT4
           index = "rgba".indexOf(dimension);
           index = (index == -1) ? "xyzw".indexOf(dimension) : index;
           index = (index == -1) ? "stpq".indexOf(dimension) : index;
       }
       
       return index;
    }
    
    //--------------------------------------------------------------------------
    //
    //  IBitmapFilter/BaseFilter
    //
    //--------------------------------------------------------------------------
        
    /**
     * @private
     * Notify of a change to our filter, so that filter stack is ultimately 
     * re-applied by the framework.
     */     
    public function notifyFilterChanged():void
    {
        dispatchEvent(new Event(BaseFilter.CHANGE));
    }

    /**
     * @private 
     * Returns a native flash.filters.ShaderFilter instance suitable
     * for application in a DisplayObject filter stack.
     */ 
    public function clone():BitmapFilter
    {
        var instance:flash.filters.ShaderFilter;
        if (_shader)
        {
            _shader.precisionHint = _precisionHint ? 
                _precisionHint : _shader.precisionHint;
            instance = new flash.filters.ShaderFilter(_shader);
            instance.bottomExtension = _bottomExtension;
            instance.topExtension = _topExtension;
            instance.leftExtension = _leftExtension;
            instance.rightExtension = _rightExtension;
        }
    
        return instance;
    }
    
    //--------------------------------------------------------------------------
    //
    //  IEventDispatcher
    //
    //--------------------------------------------------------------------------

    /**
     * @private
     */  
    private var eventDispatcher:EventDispatcher;
 
    /**
     * @private
     */ 
    public function addEventListener(type:String, listener:Function, useCapture:Boolean = false, 
            priority:int = 0, useWeakReference:Boolean = false):void 
    {
        eventDispatcher.addEventListener(type, listener, useCapture, priority, useWeakReference);
    }

    /**
     * @private
     */ 
    public function dispatchEvent(event:Event):Boolean 
    {
        return eventDispatcher.dispatchEvent(event);
    }

    /**
     * @private
     */ 
    public function hasEventListener(type:String):Boolean 
    {
        return eventDispatcher.hasEventListener(type);
    }

    /**
     * @private
     */  
    public function removeEventListener(type:String, listener:Function, useCapture:Boolean = false):void 
    {
        eventDispatcher.removeEventListener(type, listener, useCapture);
    }

    /**
     * @private
     */  
    public function willTrigger(type:String):Boolean 
    {
        return eventDispatcher.willTrigger(type);
    }
    
}  

}  
